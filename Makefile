diff: */*
	git checkout -- index.xml
	reapack-index --rebuild --no-commit
	git diff -- index.xml

commit: */*
	git checkout -- index.xml
	reapack-index --rebuild --commit
	git log -1
	git diff HEAD~

