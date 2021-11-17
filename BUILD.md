https://github.com/cfillion/reapack-index

### Installing

```
$ GEM_HOME=$HOME/bin/gem GEM_PATH=/Library/Ruby/Gems/2.6.0:$HOME/bin/gem gem install --install-dir /Users/ershov/bin/gem reapack-index
$ GEM_HOME=$HOME/bin/gem GEM_PATH=/Library/Ruby/Gems/2.6.0:$HOME/bin/gem/gem gem uninstall nokogiri
$ GEM_HOME=$HOME/bin/gem GEM_PATH=/Library/Ruby/Gems/2.6.0:$HOME/bin/gem/gem gem inst nokogiri --platform x86_64-darwin --install-dir $HOME/bin/gem
$ GEM_HOME=$HOME/bin/gem GEM_PATH=/Library/Ruby/Gems/2.6.0:$HOME/bin/gem/gem gem inst pandoc --platform x86_64-darwin --install-dir $HOME/bin/gem
$ cat ~/bin/reapack-index
#!/bin/bash
GEM_HOME=$HOME/bin/gem GEM_PATH=/Library/Ruby/Gems/2.6.0:$HOME/bin/gem PATH="$PATH:$HOME/bin/gem/bin" ~/bin/gem/bin/reapack-index "$@"
```

