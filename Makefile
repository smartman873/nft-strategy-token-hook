.PHONY: bootstrap test coverage demo-local demo-testnet demo-nft-acquire demo-all verify-commits

bootstrap:
	./scripts/bootstrap.sh

test:
	forge test -vvv

coverage:
	forge coverage --report lcov

demo-local:
	./scripts/demo-local.sh

demo-testnet:
	./scripts/demo-testnet.sh

demo-nft-acquire:
	forge test --match-test test_CanAcquireNftAfterRevenueThreshold -vvv

demo-all: demo-local demo-nft-acquire

verify-commits:
	./scripts/verify_commits.sh
