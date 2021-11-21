diff: */*
	git checkout -- index.xml
	reapack-index --rebuild --no-commit
	git diff -- index.xml
	git checkout -- index.xml
	echo "Remember to commit any uncommitted changes!"
	git status -s */*

commit: */*
	git checkout -- index.xml
	reapack-index --rebuild --commit
	git log -1
	git diff HEAD~
	echo "Remember to commit any uncommitted changes!"
	git status -s */*

reset:
	git checkout -- index.xml

amend:
	git add */*
	git commit --amend --no-edit
	git log -1

.PHONY:

.SILENT:

