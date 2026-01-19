.PHONY: status log push describe new squash

# Show working copy status
status:
	jj status

# Show commit log
log:
	jj log

# Push to remote
push:
	jj git push

# Describe current commit (usage: make describe MSG="commit message")
describe:
	jj describe -m "$(MSG)"

# Create new commit
new:
	jj new

# Squash into parent
squash:
	jj squash
