#!/bin/bash

# Fail on any error
set -eo pipefail

# Display commands being run
set -x

# Only run the linter on go1.11, since it needs type aliases (and we only care about its output once).
# TODO(deklerk) We should pass an environment variable from kokoro to decide this logic instead.
if [[ `go version` != *"go1.11"* ]]; then
    exit 0
fi

pwd

try3() { eval "$*" || eval "$*" || eval "$*"; }

try3 go get -u \
  golang.org/x/tools/cmd/goimports \
  honnef.co/go/tools/cmd/staticcheck

# Look at all .go files (ignoring .pb.go files) and make sure they have a Copyright. Fail if any don't.
git ls-files "*[^.pb].go" | xargs grep -L "\(Copyright [0-9]\{4,\}\)" 2>&1 | tee /dev/stderr | (! read)
gofmt -s -d -l . 2>&1 | tee /dev/stderr | (! read)
goimports -l . 2>&1 | tee /dev/stderr | (! read)

# Runs the linter. Regrettably the linter is very simple and does not provide the ability to exclude rules or files,
# so we rely on inverse grepping to do this for us.
#
# Piping a bunch of greps may be slower than `grep -vE (thing|otherthing|anotherthing|etc)`, but since we have a good
# amount of things we're excluding, it seems better to optimize for readability.
#
# Note: since we added the linter after-the-fact, some of the ignored errors here are because we can't change an
# existing interface. (as opposed to us not caring about the error)
golint ./... 2>&1 | ( \
    grep -vE "gen\.go" | \
    grep -vE "receiver name [a-zA-Z]+[0-9]* should be consistent with previous receiver name" | \
    grep -vE "exported const AllUsers|AllAuthenticatedUsers|RoleOwner|SSD|HDD|PRODUCTION|DEVELOPMENT should have comment" | \
    grep -v "exported func Value returns unexported type pretty.val, which can be annoying to use" | \
    grep -v "ExecuteStreamingSql" | \
    grep -vE "pubsub\/pstest\/fake\.go.+should have comment or be unexported" | \
    grep -v "ClusterId" | \
    grep -v "InstanceId" | \
    grep -v "firestore.arrayUnion" | \
    grep -v "firestore.arrayRemove" | \
    grep -v "maxAttempts" | \
    grep -v "UptimeCheckIpIterator" | \
    grep -vE "apiv[0-9]+" | \
    grep -v "ALL_CAPS" | \
    grep -v "go-cloud-debug-agent" | \
    grep -v "mock_test" | \
    grep -v "internal/testutil/funcmock.go" | \
    grep -v "internal/backoff" | \
    grep -v "internal/trace" | \
    grep -v "a blank import should be only in a main or test package" | \
    grep -vE "\.pb\.go:" || true) | tee /dev/stderr | (! read)

# TODO(deklerk) It doesn't seem like it, but is it possible to glob both before
# and after the colon? Then we could do *go-cloud-debug-agent*:*
staticcheck -ignore '
*:S1007
*:SA1019
cloud.google.com/go/firestore/internal/doc-snippets.go:*
cloud.google.com/go/functions/metadata/metadata_test.go:SA1012
cloud.google.com/go/cmd/go-cloud-debug-agent/internal/controller/client_test.go:*
cloud.google.com/go/cmd/go-cloud-debug-agent/internal/debug/dwarf/frame.go:*
cloud.google.com/go/cmd/go-cloud-debug-agent/internal/debug/dwarf/typeunit.go:*
cloud.google.com/go/cmd/go-cloud-debug-agent/internal/debug/dwarf/const.go:*
cloud.google.com/go/cmd/go-cloud-debug-agent/internal/debug/dwarf/line.go:*
cloud.google.com/go/cmd/go-cloud-debug-agent/internal/debug/server/server.go:*
cloud.google.com/go/cmd/go-cloud-debug-agent/internal/debug/server/dwarf.go:*
cloud.google.com/go/cmd/go-cloud-debug-agent/internal/debug/server/eval.go:*
cloud.google.com/go/cmd/go-cloud-debug-agent/internal/debug/server/value.go:*
cloud.google.com/go/cmd/go-cloud-debug-agent/internal/debug/elf/file.go:*
cloud.google.com/go/cmd/go-cloud-debug-agent/internal/breakpoints/breakpoints_test.go:*
cloud.google.com/go/cmd/go-cloud-debug-agent/internal/debug/gosym/pclntab_test.go:*
cloud.google.com/go/cmd/go-cloud-debug-agent/debuglet.go:*
cloud.google.com/go/translate/internal/translate/v2/translate-nov2016-gen.go:*
cloud.google.com/go/storage/bucket.go:S1002
cloud.google.com/go/spanner/value.go:S1025
cloud.google.com/go/pubsub/integration_test.go:S1012
cloud.google.com/go/internal/fields/fold.go:S1008
cloud.google.com/go/httpreplay/internal/proxy/debug.go:*
cloud.google.com/go/bigtable/internal/cbtconfig/cbtconfig.go:ST1005
cloud.google.com/go/bigtable/cmd/cbt/cbt.go:ST1005
cloud.google.com/go/asset/v1beta1/doc.go:*
cloud.google.com/go/spanner/value_test.go:S1019
cloud.google.com/go/bigtable/reader.go:S1002
cloud.google.com/go/internal/btree/btree.go:U1000
' ./...
