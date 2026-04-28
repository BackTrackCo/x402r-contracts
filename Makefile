# Makefile for x402r-contracts deployment and management

.PHONY: help deploy verify-owner test coverage clean format slither fuzz gas-snapshot gas-check

# Default target
help:
	@echo "x402r-contracts Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  deploy            - Deploy canonical addresses via CREATE2 (CreateX guarded)"
	@echo "  verify-owner      - Verify owner address is multisig"
	@echo "  test              - Run test suite"
	@echo "  coverage          - Generate test coverage report"
	@echo "  format            - Run forge fmt"
	@echo "  slither           - Run Slither analysis"
	@echo "  fuzz              - Run Echidna fuzzing"
	@echo "  gas-snapshot      - Update gas snapshot"
	@echo "  gas-check         - Check for gas regressions"
	@echo "  clean             - Clean build artifacts"
	@echo ""
	@echo "Example usage:"
	@echo "  make deploy RPC_URL=https://sepolia.base.org"

# Canonical CREATE2 deploy (single script for all chains).
# Set CANONICAL_OWNER and CANONICAL_FEE_RECIPIENT in script/DeployCreate2.s.sol
# before running. The script require()-guards both at runtime.
deploy:
	@if [ -z "$$RPC_URL" ]; then \
		echo "❌ ERROR: RPC_URL not set"; \
		echo "Usage: make deploy RPC_URL=https://..."; \
		exit 1; \
	fi
	@echo "🚀 Running CREATE2 canonical deploy against $$RPC_URL"
	@echo ""
	forge script script/DeployCreate2.s.sol \
		--rpc-url $$RPC_URL \
		--broadcast \
		--verify \
		--slow \
		-vvv

# Verify owner address is a contract
verify-owner:
	@if [ -z "$$OWNER_ADDRESS" ]; then \
		echo "❌ ERROR: OWNER_ADDRESS not set"; \
		echo "Usage: make verify-owner OWNER_ADDRESS=0x... RPC_URL=https://..."; \
		exit 1; \
	fi
	@if [ -z "$$RPC_URL" ]; then \
		echo "❌ ERROR: RPC_URL not set"; \
		echo "Usage: make verify-owner OWNER_ADDRESS=0x... RPC_URL=https://..."; \
		exit 1; \
	fi
	@echo "Checking owner at address: $$OWNER_ADDRESS"
	@CODE=$$(cast code $$OWNER_ADDRESS --rpc-url $$RPC_URL); \
	if [ "$$CODE" = "0x" ]; then \
		echo "❌ Owner is an EOA (Externally Owned Account)"; \
		echo "   Mainnet deployment requires multisig"; \
		exit 1; \
	else \
		echo "✅ Owner is a contract"; \
		echo "   Manually verify it's a multisig on block explorer"; \
	fi

# Run test suite
test:
	@echo "Running test suite..."
	forge test -vv

# Generate coverage report
coverage:
	@echo "Generating coverage report..."
	forge coverage --report summary
	@echo ""
	@echo "For detailed HTML report:"
	@echo "  forge coverage --report lcov"
	@echo "  genhtml lcov.info -o coverage"
	@echo "  open coverage/index.html"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	forge clean
	rm -rf coverage/
	rm -f lcov.info

# Format code
format:
	@echo "Formatting Solidity code..."
	forge fmt

# Run Slither analysis
slither:
	@echo "Running Slither analysis..."
	slither . --config-file slither.config.json

# Run Echidna fuzzing
fuzz:
	@echo "Running Echidna fuzzing (100k sequences)..."
	echidna . --contract PaymentOperatorInvariants --config echidna.yaml

# Update gas snapshot
gas-snapshot:
	@echo "Updating gas snapshot..."
	forge snapshot

# Check gas regression
gas-check:
	@echo "Checking for gas regressions..."
	forge snapshot --check
