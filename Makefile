# Makefile for x402r-contracts deployment and management

.PHONY: help deploy-testnet deploy-mainnet verify-owner test coverage clean

# Default target
help:
	@echo "x402r-contracts Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  deploy-testnet    - Deploy to testnet (allows EOA owner)"
	@echo "  deploy-mainnet    - Deploy to mainnet (requires multisig)"
	@echo "  verify-owner      - Verify owner address is multisig"
	@echo "  test              - Run test suite"
	@echo "  coverage          - Generate test coverage report"
	@echo "  clean             - Clean build artifacts"
	@echo ""
	@echo "Example usage:"
	@echo "  make deploy-testnet"
	@echo "  make deploy-mainnet OWNER_ADDRESS=0x1234..."

# Testnet deployment (Base Sepolia)
deploy-testnet:
	@echo "🧪 Deploying to testnet (Base Sepolia)..."
	@echo ""
	forge script script/DeployTestnet.s.sol \
		--rpc-url base-sepolia \
		--broadcast \
		--verify \
		-vvv

# Mainnet deployment (Base)
deploy-mainnet:
	@echo "⚠️  MAINNET DEPLOYMENT"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@if [ -z "$$OWNER_ADDRESS" ]; then \
		echo "❌ ERROR: OWNER_ADDRESS not set"; \
		echo ""; \
		echo "Usage: make deploy-mainnet OWNER_ADDRESS=0x..."; \
		exit 1; \
	fi
	@echo "Owner address: $$OWNER_ADDRESS"
	@echo ""
	@echo "🔍 Verify this is a multisig on Basescan:"
	@echo "   https://basescan.org/address/$$OWNER_ADDRESS"
	@echo ""
	@read -p "⚠️  Confirm owner is multisig contract [y/N]: " confirm && [ "$$confirm" = "y" ] || (echo "Deployment cancelled" && exit 1)
	@echo ""
	@echo "🚀 Starting mainnet deployment..."
	@echo ""
	forge script script/DeployProduction.s.sol \
		--rpc-url base \
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
