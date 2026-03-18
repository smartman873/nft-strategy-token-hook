.PHONY: bootstrap test coverage coverage-check demo-local demo-testnet demo-nft-acquire demo-all verify-commits

bootstrap:
	./scripts/bootstrap.sh

test:
	forge test -vvv

coverage:
	forge coverage --exclude-tests --no-match-coverage "script|test|lib" --report summary

coverage-check:
	@tmpfile="$$(mktemp)"; \
	forge coverage --exclude-tests --no-match-coverage "script|test|lib" --report summary | tee "$$tmpfile"; \
	grep -Eq 'Total[[:space:]]+\|[[:space:]]+100\.00%.*100\.00%.*100\.00%.*100\.00%' "$$tmpfile"; \
	rm -f "$$tmpfile"

demo-local:
	./scripts/demo-local.sh

demo-testnet:
	./scripts/demo-testnet.sh

demo-nft-acquire:
	forge test --match-test test_CanAcquireNftAfterRevenueThreshold -vvv

demo-all: demo-local demo-nft-acquire

verify-commits:
	./scripts/verify_commits.sh
