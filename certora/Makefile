# The Certora Prover cannot handle the `Take` event, whose emission is dropped
# for verification. To avoid touching `src/`, the specs run against a `munged/`
# copy of `src/` with `applyHarness.patch` applied on top.

munged: $(wildcard ../src/*.sol) $(wildcard ../src/**/*.sol) applyHarness.patch
	rm -rf munged
	cp -rf ../src munged
	patch -p0 -d munged < applyHarness.patch

# Regenerate applyHarness.patch after manually editing files in munged/.
record:
	diff -ruN ../src munged | sed 's+../src/++g' | sed 's+munged/++g' > applyHarness.patch || true

clean:
	rm -rf munged

.PHONY: record clean
