#!/usr/bin/perl -w

# TODO: all identifiers are case insensitive
# TODO: add number parsing so that "." is not treated as member access
# TODO: fix "unused" warning for variables-by-reference
# TODO: functions "overload" by number of args (but 0 and 1 args are the same)
# TODO: section-local functions
# TODO: import paths are relative to the current file
# TODO: global() and globals() are hiding global vars that are not listed

use warnings;
use strict;
use v5.12.0;

my $DEBUG = 0;

my $pos = 0;
my $filename = "";
my $lineno = 1;
my $linepos = 1;
my $level = 0;
my $file_level = 0;
my %files;        # {file => level}
my @errors = ();  # [file, line, pos, text]

my %vars;         # name => [file, line, col]
my %vars_init;    # name => 1

my $commentCpp = qr{(?://[^\n]*+\n)}ms;
my $commentC = qr{(?:/\*.*?\*/)}ms;
my $spaces = qr{(?:[ \t\r\n]+)}ms;
my $__ = qr{(?:$commentCpp|$commentC|$spaces)}ms;
my $identifier = qr{(?:[a-zA-Z_][a-zA-Z0-9_]*+)}ms;
my $identifierx = qr{(?:[a-zA-Z_][a-zA-Z0-9_\.]*+)}ms;
my $squotestr = qr{(?:'([^'\\]|\\.)*')}ms;
my $dquotestr = qr{(?:"([^"\\]|\\.)*")}ms;
my $str = qr{(?:$squotestr|$dquotestr)}ms;
my $paren = qr{(?:[\[\]\{\}\(\)])}ms;
my $operator = qr{(?:[\+\-\*\/<>\|\&\%\^=])}ms;

my %kw = map { ($_, 1) } qr/while loop function/;

my %specialvars = map { ($_, 1) } (
  (map {"spl$_"} (0..63)),
  (map {"slider$_"} (1..64)),
  (map {"reg0$_"} (0..9)),
  (map {"reg$_"} (10..99)),
  # _global* ?
  qw/this
     pi e phi
     gmem
     trigger srate num_ch samplesblock tempo play_state play_position beat_position
     ts_num ts_denom ext_noinit ext_nodenorm pdc_delay pdc_bot_ch pdc_top_ch pdc_midi
     gfx_r gfx_g gfx_b gfx_a gfx_w gfx_h gfx_x gfx_y gfx_mode gfx_clear gfx_dest
     gfx_texth gfx_ext_retina gfx_ext_flags mouse_x mouse_y mouse_cap
     midi_bus ext_midi_bus/
);

my $funcname;
my $functhisname;
my $funclevel;
my @funcargs;
my @funclocalvars;
my @funcglobalvars;
my %funcimplicitglobalvars;
my @funcinstancevars;
my @funcargsbyref;
my %funclocalvars;          # name => [file, line, col], same as global %vars
my %funcobjrefs;            # name => ?   # e.g. "this.field" or "o.field" where "o" is a by-ref arg
my %funcobjinit;            # name => ?   # e.g. "this.field" or "o.field" where "o" is a by-ref arg
my %funclocalinit;          # name => ?   # e.g. "this.field" or "o.field" where "o" is a by-ref arg
my %funcdeferredcalls;      # [ { name => , args => [] } ]
my $funcusesthis;

my $funcall_level = -1;
my @funcall_args;
my $last_var = "";

# name => info
#my %functions;
my %functions = (
  gfx_measurestr => {
    name => "gfx_measurestr", pos => ["internal", 0, 0], args => [qw/str w h/], byref => [qw/w h/], objrefs => [qw/w h/], objinit => [qw/w h/],
  },
  gfx_getpixel => {
    name => "gfx_getpixel", pos => ["internal", 0, 0], args => [qw/r g b/], byref => [qw/r g b/], objrefs => [qw/r g b/], objinit => [qw/r g b/],
  },
  midirecv => {
    name => "midirecv", pos => ["internal", 0, 0], args => [qw/offset msg1 msg2 msg3/], byref => [qw/offset msg1 msg2 msg3/], objrefs => [qw/offset msg1 msg2 msg3/], objinit => [qw/offset msg1 msg2 msg3/],
  },
  midirecv_str => {
    name => "midirecv_str", pos => ["internal", 0, 0], args => [qw/offset string/], byref => [qw/offset string/], objrefs => [qw/offset string/], objinit => [qw/offset string/],
  },
  midirecv_buf => {
    name => "midirecv_buf", pos => ["internal", 0, 0], args => [qw/offset buf maxlen/], byref => [qw/offset/], objrefs => [qw/offset/], objinit => [qw/offset/],
  },
  time => {
    name => "time", pos => ["internal", 0, 0], args => [qw/v/], byref => [qw/v/], objrefs => [qw/v/], objinit => [qw/v/],
  },
  time_precise => {
    name => "time_precise", pos => ["internal", 0, 0], args => [qw/v/], byref => [qw/v/], objrefs => [qw/v/], objinit => [qw/v/],
  },
  file_var => {
    name => "file_var", pos => ["internal", 0, 0], args => [qw/handle variable/], byref => [qw/variable/], objrefs => [qw/variable/], objinit => [qw/variable/],
  },
  file_string => {
    name => "file_string", pos => ["internal", 0, 0], args => [qw/handle str/], byref => [qw/str/], objrefs => [qw/str/], objinit => [qw/str/],
  },
  sprintf => {
    name => "sprintf", pos => ["internal", 0, 0], args => [qw/str - - - - - - - - - - - - - - - - - - - -/], byref => [qw/str/], objrefs => [qw/str/], objinit => [qw/str/],
  },
  strcpy => {
    name => "strcpy", pos => ["internal", 0, 0], args => [qw/str src/], byref => [qw/str/], objrefs => [qw/str/], objinit => [qw/str/],
  },
  strncpy => {
    name => "strncpy", pos => ["internal", 0, 0], args => [qw/str src len/], byref => [qw/str/], objrefs => [qw/str/], objinit => [qw/str/],
  },
  strcpy_from => {
    name => "strcpy_from", pos => ["internal", 0, 0], args => [qw/str src offset/], byref => [qw/str/], objrefs => [qw/str/], objinit => [qw/str/],
  },
  strcpy_substr => {
    name => "strcpy_substr", pos => ["internal", 0, 0], args => [qw/str src offset len/], byref => [qw/str/], objrefs => [qw/str/], objinit => [qw/str/],
  },
  strcpy_fromslider => {
    name => "strcpy_fromslider", pos => ["internal", 0, 0], args => [qw/str slider/], byref => [qw/str/], objrefs => [qw/str/], objinit => [qw/str/],
  },
  match => {
    name => "match", pos => ["internal", 0, 0],
    args => [qw/needle haystack arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9 arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19 arg20/],
    byref => [qw/arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9 arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19 arg20/],
    objrefs => [qw/arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9 arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19 arg20/],
    objinit => [qw/arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9 arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19 arg20/],
  },
);

sub Pos() { if (!defined(pos()) || pos() < $pos) { pos() = $pos; } }
sub Pos1() { if (!defined(pos()) || pos() < $pos) { pos() = (++$pos); } }

sub filename() { $filename || $ARGV }

sub in(@) {
  my $v = shift;
  for my $e (@_) { return 1 if $v eq $e; }
  return undef;
}

sub startswith($$) {
  my ($txt, $needle) = @_;
  return substr($txt, 0, length($needle)) eq $needle;
}

sub Error {
  print filename().":$lineno:$linepos: ", @_, "\n";
  exit;
}

sub Warn {
  push @errors, [filename(), $lineno, $linepos, (join "", @_)];
}

sub FuncStateClear() {
  $funcname = undef;
  $functhisname = undef;
  $funclevel = undef;
  @funcargs = ();
  @funclocalvars = ();
  @funcglobalvars = ();
  %funcimplicitglobalvars = ();
  @funcinstancevars = ();
  @funcargsbyref = ();
  %funclocalvars = ();
  %funcobjrefs = ();
  %funcobjinit = ();
  %funclocalinit = ();
  %funcdeferredcalls = ();
  $funcusesthis = 0;
  $last_var = "";
}

sub NormalizeThis($) {
  my $var = $_[0];
  my ($head, $tail) = split /\./, $var;
  if (defined($functhisname) and $head eq $functhisname) {
    print filename().":$lineno:$linepos: replace 'this' alias <$_[0]> -> <this.$tail>\n" if $DEBUG;
    $funcusesthis = 1;
    return "this.".$tail;
  }
  if (in($head, @funcinstancevars)) {
    print filename().":$lineno:$linepos: instance var use <$var> -> <this.$var>\n" if $DEBUG;
    $funcusesthis = 1;
    return "this.".$var;
  }
  if ($head eq 'this') {
    $funcusesthis = 1;
  }
  return $var;
}
sub AddGlobalVar($;$) {
  my $var = $_[0];
  my $count = $_[1] || 1;
  do {
    for (1 .. $count) { push @{$vars{$var}}, [filename(), $lineno, $linepos]; }
  } while ($var =~ s/\.[^.]*$//);   # use all parent objects too
}
sub AddVar($;$) {
  my $var = shift;
  my $count = shift || 1;
  return if exists $specialvars{$var};   # this also drops bare 'this'

  if ($var =~ m{^($identifier)\.}) {
    my $obj = $1;
    if ($obj eq 'this' || in($obj, @funcargsbyref)) {
      print filename().":$lineno:$linepos: object ref use <$obj>\n" if $DEBUG;
      $funcobjrefs{$var} += $count;
      $obj eq 'this' and !$funcname and Warn "Use of 'this' outside of function.";
      $obj ne 'this' and push @{$funclocalvars{$obj}}, [filename(), $lineno, $linepos];  # mark usage of function arg
      return;
    }
  }

  if (in($var, @funclocalvars) || in($var, @funcargs)) {
    print "= local var: <$var>\n" if $DEBUG;
    for (1 .. $count) { push @{$funclocalvars{$var}}, [filename(), $lineno, $linepos]; }
  } else {
    if ($funcname && !in($var, @funcglobalvars)) {
      #Warn "'$var': Global variable not listed in 'global' list.";
      print "= implicit global var: <$var>\n" if $DEBUG;
      $funcimplicitglobalvars{$var} += $count;
    } else {
      print "= global var: <$var>\n" if $DEBUG;
    }
    AddGlobalVar($var, $count);
  }
}

sub AddGlobalVarInit($) {
  my $var = $_[0];
  do {
    $vars_init{$var} = 1;
  } while ($var =~ s/\.[^.]*$//);   # use all parent objects too
}
sub AddVarInit($) {
  my $var = shift;
  return if (!$var || exists $specialvars{$var});   # this also drops bare 'this'

  print filename().":$lineno:$linepos: variable init: <$var>\n" if $DEBUG;

  if ($var =~ m{^($identifier)\.}) {
    my $obj = $1;
    if ($obj eq 'this' || in($obj, @funcargsbyref)) {
      print filename().":$lineno:$linepos: ... object ref <$obj>\n" if $DEBUG;
      $funcobjinit{$var}++;
      return;
    }
  }

  if (in($var, @funclocalvars) || in($var, @funcargs)) {
    print filename().":$lineno:$linepos: ... local\n" if $DEBUG;
    $funclocalinit{$var} = 1;
  } else {
    print filename().":$lineno:$linepos: ... global\n" if $DEBUG;
    AddGlobalVarInit($var);
  }
}

sub AdvanceLineno() {
  my $val = $&;
  my $nl = ($val =~ tr/\n/\n/);
  if ($nl) {
    $lineno += $nl;
    $linepos = length($val) - rindex($val, "\n");
    #print "        line $lineno\n";
  } else {
    $linepos += length($val);
  }
  $pos = pos();
}

sub ParseIntro() {
  while (m{
      \G
      #(?<commentCpp>//[^\n]*+\n) |
      #(?<commentC>/\*.*?\*/) |
      (?<slider>^slider\d+:[^\n]+\n) |
      (?<import>^import[^\n\r]++) |
      (?<sectionStart>(?=^@)) |
      (?<line>^[^\n]*\n) |
      (?<spaces>[ \t]++) |
      (?<newline>\n) |
      (?<char>.)
      }gxms)
  {
    #print "@{[keys %+]}: <$&>\n";
    Error "match error" if 0+(keys %+) != 1;
    my ($token, $val) = ( (keys %+)[0], $& );
    print filename().":$lineno:$linepos:".pos().":(intro):$token: <$val>\n" if $DEBUG;

    AdvanceLineno();
    last if $token eq 'sectionStart';
    if ($token eq 'slider') {
      if ($val =~ m{[^:]+:($identifier)=}) {
        my $var = $1;
        AddVar($var, 2);   # never warn about single usage
        AddVarInit($var);
      }
    } elsif ($token eq 'import') {
      ($val =~ m{^import\s+([^\n]+)}) ?  ImportFile($1) : Warn "Import error: no file name.";
    }
  }
}

sub ParseCommon() {
  while (m{
      \G
      (?<ignore>${__}+) |
      (?<str>$str) |
      (?<sectionStart>^@[^\n]+\n) |
      (?<functionStart>(?=function$__)) |
      (?<hexnum>[\$0]x[0-9a-fA-F]*+) |
      (?<variable_assign>$identifierx(?=${__}*=(?!=))) |
      (?<variable>$identifierx(?!${__}*\()) |
      (?<funcall>$identifierx(?=${__}*\()) |
      (?<paren>[\[\]\{\}\(\)]) |
      (?<comma>,) |
      (?<semicolon>;) |
      (?<escapechar>\\.) |
      (?<operator_modassign>[+\-*/&|!~%^<>]=) |
      (?<operator>[+\-*/&|!~%^<>]) |  # this doesn't include ? : =
      (?<spaces>[ \t]++) |
      (?<char>.)
      }gxms)
  {
    #print "@{[keys %+]}: <$&>\n";
    Error "match error" if 0+(keys %+) != 1;

    AdvanceLineno();

    my ($token, $val) = ( (keys %+)[0], $& );
    print filename().":$lineno:$linepos:".pos().":($level $funcall_level):$token: <$val>\n" if $DEBUG;

    if ($token eq 'paren') {
      if ($val =~ /[\[\(\{]/) { $level++; }
      if ($val =~ /[\]\)\}]/) {
        $level--;
        if ($level < 0) { Error "')' at top level."; }
        if ($funcname && $level <= $funclevel) {
          OnEndOfFunction();
        }
        if ($funcall_level == $level) {
          push @funcall_args, ($last_var || "");   # () will result in a single-arg call but that's ok
          print filename().":$lineno:$linepos:".pos().":($level $funcall_level): end of funcall\n" if $DEBUG;
          last;
        }
      }
    } elsif ($token eq 'functionStart') {
      ParseFunction();
    } elsif ($token eq 'funcall') {
      $val ne 'while' && $val ne 'loop' and ParseFuncall($val);
    } elsif ($token eq 'variable') {
      my $var = NormalizeThis($val);
      AddVar($var);
      defined $last_var and $last_var = $var;   # TODO: handle (?:) - use both paths
    } elsif ($token eq 'variable_assign') {
      my $var = NormalizeThis($val);
      AddVar($var);
      AddVarInit($var);
      defined $last_var and $last_var = $var;   # TODO: handle (?:) - use both paths
    } elsif ($token eq 'operator_modassign') {
      # TODO: how to prevent the current $last_var from changing?
    } elsif ($token eq 'operator') {
      $last_var = undef;   # will not be updated
    } elsif ($token eq 'semicolon') {
      $last_var = "" if !defined $last_var;
    } elsif ($token eq 'comma') {
      #$funcall_level == -1 and Warn "Unexpected ',' not in function arguments list.";
      if ($funcall_level >= 0 && $level == $funcall_level + 1) {
        push @funcall_args, ($last_var || "");
      }
      $last_var = "" if !defined $last_var;
    }
  }
}

sub ParseFunction() {
  $funcname and Error "Can't define function inside function.";
  $level and Warn "Function definition not on top level.";

  FuncStateClear();

  m{\Gfunction$__+}gxms or Error "syntax error in function: 'function' keyword expected.";
  AdvanceLineno();

  while (m{\G($identifierx)$__*\($__*}gxms) {
    AdvanceLineno();
    my $id = $1;
    print filename().":$lineno:$linepos:".pos().":($level): function id: <$id>\n" if $DEBUG;
    my @args = ();
    while (m{\G($identifierx)$__*([*]?)$__*([,]?)$__*}gxms) {
      AdvanceLineno();
      print filename().":$lineno:$linepos:".pos().":($level): function arg <$1> ref:<$2>\n" if $DEBUG;
      push @args, $1;
      $2 and push @funcargsbyref, $1;
    }
    Pos();
    m{\G$__*\)$__*}gxms or Error "syntax error in function: ')' expected.";
    AdvanceLineno();
    !$funcname ? do {
      #($functhisname, $funcname) = ("this", (split /\./, $id, 2))[-2, -1];
      ($functhisname, $funcname) = ($id =~ m{^($identifier)\.(.*)$}) ? ($1, $2) : (undef, $id);
      @funcargs = @args;
    } :
    $id eq "local" ? @funclocalvars = @args :
    $id eq "global"   || $id eq "globals" ? @funcglobalvars = @args :  # 'globals' is invalid but it's used in a lot of Cockos' files
    $id eq "instance" || $id eq "static"  ? @funcinstancevars = @args :
    Warn "Function syntax error: unknown modifier '$id'.";
  }
  Pos();
  @funclocalvars = grep {!in($_, @funcargs)} @funclocalvars;   # some function args might be listed in local() - remove them
  $funclevel = $level;
  print filename().":$lineno:$linepos:".pos().":($level): function $funcname(@funcargs) local(@funclocalvars) global(@funcglobalvars) instance(@funcinstancevars) refs(@funcargsbyref):\n" if $DEBUG;

  exists $functions{$funcname} and Warn "Function '$funcname' redefinition: previously was defined here: ".join ":", @{$functions{$funcname}->{pos}};
}

sub OnEndOfFunction() {
  print filename().":$lineno:$linepos:".pos().":($level $funcall_level): end of function\n" if $DEBUG;

  push @errors,
  map {
    my $loc = $funclocalvars{$_}->[0];
    [$loc->[0], $loc->[1], $loc->[2], "Function '$funcname': '$_': Function-local variable is used only once."]
  }
  grep {!in($_,@funcargs) && @{$funclocalvars{$_}} == 1}
  keys %funclocalvars;

  push @errors,
  map {
    [filename(), $lineno, $linepos, "Function '$funcname': '$_': ".(in($_,@funcargs)?"Function argument":"Function-local variable")." is never used."]
  }
  grep {!exists $funclocalvars{$_}}
  @funcargs, @funclocalvars;

  push @errors,
  map {
    [filename(), $lineno, $linepos, "Function '$funcname': '$_': Function-local variable is never initialized."]
  }
  grep {exists $funclocalvars{$_} and !exists $funclocalinit{$_}}
  @funclocalvars;

  ($functhisname || @funcinstancevars) && !$funcusesthis and Warn "Function '$funcname' is object-like but doesn't use any instance vars or funcs.";

  # %funcimplicitglobalvars and Warn "Function '$funcname': Implicit globals: ".join " ", sort keys %funcimplicitglobalvars;
  # %funcobjrefs and Warn "Function '$funcname': Object references: ".join " ", sort keys %funcobjrefs;

  $functions{$funcname} = {
    name => $funcname,              # Pure function name without object
    thisname => $functhisname,
    usesthis => $funcusesthis,
    pos => [filename(), $lineno, $linepos],
    args => [@funcargs],
    byref => [@funcargsbyref],
    localvars => [@funclocalvars],
    globalvars => [@funcglobalvars],
    instancevars => [@funcinstancevars],
    objrefs => [sort keys %funcobjrefs],
    objinit => [sort keys %funcobjinit],
    calls => [sort {$a->{name} cmp $b->{name}} values %funcdeferredcalls],
  };

  use Data::Dumper;
  print Dumper($functions{$funcname}) if $DEBUG;

  FuncStateClear();
}

sub ParseFuncall($) {
  my $funcallname = NormalizeThis($_[0]);
  if (in($funcallname, @funcinstancevars)) { $funcallname = "this.$funcallname"; }

  my $funcall_level_ = $funcall_level;  $funcall_level = $level;
  my @funcall_args_ = @funcall_args;    @funcall_args = ();
  $last_var = "";

  ParseCommon();

  print filename().":$lineno:$linepos: function call: $funcallname(@{[map {qq{<$_>}} @funcall_args]})\n" if $DEBUG;

  TryTraceFuncall($funcallname, @funcall_args);

  $funcall_level = $funcall_level_;
  @funcall_args = @funcall_args_;
  $last_var = "";
}

sub SplitVariable($) {  # -> (object, field)
  return ((split /\./, $_[0], 2), "", "")[0,1];
}
sub SplitCallable($) {  # -> (object, field, function)
  my ($obj, $field, $func) = ("", "", $_[0]);
  $func =~ m{^($identifier)\.(.*)$} or return ("", "", $func);
  $obj = $1; $func = $2;
  $func =~ m{^(.*?)\.($identifier)$} or return ($obj, "", $func);
  $field = $1; $func = $2;
  return ($obj, $field, $func);
}
sub JoinIdentifier { join ".", grep {$_} @_; }

sub TryTraceFuncall {
  my ($name, @args) = @_;

  # If any of objects are references, defer the trace
  for my $obj (grep {$_} (SplitCallable($name), map {(SplitVariable($_))[0]} @args)) {
    if ($obj eq 'this' || in($obj, @funcargsbyref)) {
      print filename().":$lineno:$linepos: Defer call trace because '$obj' is a reference\n" if $DEBUG;
      my $func = (SplitCallable($name))[2];
      $funcdeferredcalls{"$name @funcall_args"} = {
        name => $name,              # full callable name, including objects and fields
        func => $func,              # pure function name
        ref => $functions{$func},   # Since the function can be redefined, store the current one
        args => [@args],
      };
      return;
    }
  }

  my ($obj, $field, $func) = SplitCallable($name);

  #!$obj && @{$functions{$func}->{objrefs}||[]} and Warn "Calling object-like function '$func' without an object.";
  #$obj && !@{$functions{$func}->{objrefs}||[]} && !@{$functions{$func}->{calls}||[]} and Warn "Calling simple function '$func' as an object-like.";
  !$obj && $functions{$func}->{usesthis} and Warn "Calling object-like function '$func' without an object.";
  $obj && !$functions{$func}->{usesthis} and Warn "Calling simple function '$func' as an object-like.";

  if (!@{$functions{$func}->{byref}||[]} && !@{$functions{$func}->{objrefs}||[]} && !@{$functions{$func}->{calls}||[]}) {
    print filename().":$lineno:$linepos: Skipping call trace since the function '$func' doesn't have any refs or deferred calls\n" if $DEBUG;
    return;
  }

  print filename().":$lineno:$linepos: Instant call trace: all objects are concrete and there are refs or calls in function '$func'\n" if $DEBUG;

  TraceFuncall($func, JoinIdentifier($obj, $field), @args);
}

my $trace_funcall_depth = 0;
sub TraceFuncall {
  $trace_funcall_depth < 100 or Error "too deep recursion";
  my ($func, $this, @args) = @_;
  my $finfo;

  if (!ref $func) {
    print "".("  "x$trace_funcall_depth)."... trace function call (by name): <$this>.<$func>(".(join " ", map {"<$_>"} @args).")\n" if $DEBUG;
    $finfo = $functions{$func};
    if (!$finfo) {
      print filename().":$lineno:$linepos: Not tracing '$func' since it's not defined.\n" if $DEBUG;
      return;
    }
  } else {
    $finfo = $func;
    $func = $finfo->{name};
    print "".("  "x$trace_funcall_depth)."... trace function call (by ref): <$this>.<$func>(".(join " ", map {"<$_>"} @args).")\n" if $DEBUG;
  }

  my %namedrefs;
  for (my $i = 0; $i < @args; $i++) {
    next if !$args[$i];
    my $argname = $finfo->{args}->[$i];
    next if !in($argname, @{$finfo->{byref}});
    $namedrefs{$argname} = $args[$i];
  }
  $namedrefs{this} = $this || $func;

  my %unresolvedvars;

  for my $varref (@{$finfo->{objrefs}||[]}) {
    my ($obj, $field) = split /\./, $varref, 2;
    if (exists $namedrefs{$obj}) {
      my $var = JoinIdentifier($namedrefs{$obj}, $field);
      print "".("  "x$trace_funcall_depth)."...($trace_funcall_depth) Use var by ref in '$func': $varref => $var\n" if $DEBUG;
      $trace_funcall_depth ? AddGlobalVar($var, 2) : AddVar($var, 2);   # don't know how many times this is used
    } else {
      $unresolvedvars{$obj} = 1;
    }
  }

  for my $varref (@{$finfo->{objinit}||[]}) {
    my ($obj, $field) = split /\./, $varref, 2;
    if (exists $namedrefs{$obj}) {
      my $var = JoinIdentifier($namedrefs{$obj}, $field);
      print "".("  "x$trace_funcall_depth)."...($trace_funcall_depth) Init var by ref in '$func': $varref => $var\n" if $DEBUG;
      $trace_funcall_depth ? AddGlobalVarInit($var) : AddVarInit($var);
    } else {
      $unresolvedvars{$obj} = 1;
    }
  }

  #%unresolvedvars and Warn "Unresolved objects inside function '$func': ".join ", ", sort keys %unresolvedvars;

  for my $call (@{$finfo->{calls}||[]}) {
    print "".("  "x$trace_funcall_depth)."... sub function call: $call->{name}(".(join " ", map {"<$_>"} @{$call->{args}}).")\n" if $DEBUG;
    $trace_funcall_depth++;
    my ($obj, $field, $func) = SplitCallable($call->{name});
    exists $namedrefs{$obj} and $obj = $namedrefs{$obj};
    TraceFuncall(
      $call->{ref} || $func,
      JoinIdentifier($obj, $field),
      map {
        my ($obj, $field) = SplitVariable($_);
        exists $namedrefs{$obj} and $obj = $namedrefs{$obj};
        JoinIdentifier($obj, $field);
      } @{$call->{args}}
    );
    $trace_funcall_depth--;
  }
}

sub ParseFile() {
  ParseIntro();
  ParseCommon();
  $level == 0 or Warn "Unclosed ')' at EOF.";
}


sub Check() {
  push @errors,
    map {
      my $loc = $vars{$_}->[0];
      [$loc->[0], $loc->[1], $loc->[2], "'$_': Global variable is used only once."]
    }
    grep {@{$vars{$_}} == 1}
    keys %vars;

  push @errors,
    map {
      [filename(), $lineno, $linepos, "'$_': Global variable is never initialized."]
    }
    grep {!exists $vars_init{$_}}
    keys %vars;
}


sub Print() {
  print
    join "",
    map {"$_->[0]:$_->[1]:$_->[2]: $_->[3]\n"}
    sort {
      ((exists($files{$a->[0]}) && exists($files{$b->[0]})) && ($files{$a->[0]} <=> $files{$b->[0]})) ||
      $a->[0] cmp $b->[0] ||
      $a->[1] <=> $b->[1] ||
      $a->[2] <=> $b->[2] ||
      $a->[3] cmp $b->[3]
    } @errors;
}


sub DoFile() {
  ParseFile();
  Check();
  Print();
  #print "\n" if @errors;
}

sub ImportFile($) {
  print filename().":$lineno: import <$_[0]>\n" if $DEBUG;
  if (exists $files{$_[0]}) {
    Warn "Repeated import of $_[0] ignored.";
    return;
  }

  my $pos_ = $pos;           $pos = 0;
  my $level_ = $level;       $level = 0;
  my $lineno_ = $lineno;     $lineno = 1;
  my $linepos_ = $linepos;   $linepos = 1;
  my $filename_ = $filename; $filename = $_[0];
  my $input_ = $_;
  open F, "<", $filename or Error "Can't open '$filename': $!";
  $_ = do { local $/=undef; <F>; };
  close F;

  $file_level++;
  $files{filename()} = $file_level;
  ParseFile();
  $file_level--;

  $pos = $pos_;
  $level = $level_;
  $filename = $filename_;
  $lineno = $lineno_;
  $linepos = $linepos_;
  $_ = $input_;
  pos() = $pos;

  print filename().":$lineno: import end\n" if $DEBUG;
}

$_ = do { local $/=undef; <>; } or Error "Empty input";
$files{filename()} = $file_level;
DoFile();

#print "\n  Global vars list:\n\n".(join "\n", sort keys %vars)."\n";

