# Connectcha developer commands. Run `make help` to list them.
#
# Everything runs against the local stack (Supabase CLI + Docker + iOS simulators).
# No hosted accounts are needed.

SHELL := /bin/bash
.DEFAULT_GOAL := help

# GoTrue refuses to enable phone login unless some SMS provider is configured,
# so local runs use a placeholder token. Test numbers never reach Twilio.
export SUPABASE_AUTH_SMS_TWILIO_AUTH_TOKEN ?= placeholder-local-only

ROOT := $(shell pwd)
IOS_DIR := $(ROOT)/ios
DERIVED := $(ROOT)/.derived
APP := $(DERIVED)/Build/Products/Debug-iphonesimulator/Connectcha.app
BUNDLE_ID := com.connectcha.app
SIM_A_NAME := Connectcha A
SIM_B_NAME := Connectcha B
SIM_RUNTIME := com.apple.CoreSimulator.SimRuntime.iOS-26-3
DB_URL := postgresql://postgres:postgres@127.0.0.1:54322/postgres

.PHONY: help up down reset status test-db test-functions test ios-project ios-config ios-build ios-test ios-ui-test \
        sims sim-a sim-b demo demo-stop seed-media logs

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# ----------------------------------------------------------------------------
# Backend
# ----------------------------------------------------------------------------
up: ## Start the local Supabase stack (Postgres, Auth, Storage, Edge Functions)
	supabase start

down: ## Stop the local stack (keeps data)
	supabase stop

reset: ## Recreate the database from migrations and seeds, then upload demo media
	supabase db reset
	$(MAKE) seed-media

status: ## Show local URLs and keys
	supabase status

test-db: ## Run the pgTAP access-rule suite (supabase/tests)
	supabase test db

test-functions: ## Run the Edge Function unit tests (Deno)
	cd supabase/functions && deno test --allow-env --allow-net --allow-read

test: test-db test-functions ios-test ## Run every automated test

seed-media: ## Upload demo photos and videos to local Storage
	./scripts/seed-media.sh

logs: ## Tail Edge Function logs
	docker logs -f supabase_edge_runtime_connectcha

# ----------------------------------------------------------------------------
# iOS
# ----------------------------------------------------------------------------
ios-project: ## Regenerate ios/Connectcha.xcodeproj from ios/project.yml
	cd $(IOS_DIR) && xcodegen generate

ios-config: ## Write ios/Config/Local.xcconfig from the running local stack
	./scripts/write-ios-config.sh

ios-build: ios-project ## Build the app for the simulator
	cd $(IOS_DIR) && xcodebuild -project Connectcha.xcodeproj -scheme Connectcha \
	  -destination 'generic/platform=iOS Simulator' -derivedDataPath $(DERIVED) \
	  build 2>&1 | xcbeautify --quiet

ios-ui-test: ios-project sims reset ## Reset demo data, then run the iOS UI tests (scenario walkthroughs) on simulator A
	cd $(IOS_DIR) && xcodebuild -project Connectcha.xcodeproj -scheme Connectcha \
	  -destination "platform=iOS Simulator,id=$$(./../scripts/sim-id.sh '$(SIM_A_NAME)')" \
	  -derivedDataPath $(DERIVED) -only-testing:ConnectchaUITests \
	  test 2>&1 | xcbeautify --quiet

ios-test: ios-project sims ## Run the iOS unit tests on simulator A
	cd $(IOS_DIR) && xcodebuild -project Connectcha.xcodeproj -scheme Connectcha \
	  -destination "platform=iOS Simulator,id=$$(./../scripts/sim-id.sh '$(SIM_A_NAME)')" \
	  -derivedDataPath $(DERIVED) -only-testing:ConnectchaTests \
	  test 2>&1 | xcbeautify --quiet

# ----------------------------------------------------------------------------
# Demo
# ----------------------------------------------------------------------------
sims: ## Create the two demo simulators if they don't exist
	@./scripts/ensure-sim.sh '$(SIM_A_NAME)' 'iPhone 17 Pro' '$(SIM_RUNTIME)'
	@./scripts/ensure-sim.sh '$(SIM_B_NAME)' 'iPhone 17' '$(SIM_RUNTIME)'

demo: ## Start everything: stack, reset+seed, build, two simulators signed-in ready
	./scripts/demo.sh

demo-stop: ## Shut down simulators and the push bridge (leaves the stack running)
	./scripts/demo.sh stop
