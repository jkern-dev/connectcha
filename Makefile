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
        sims sim-a sim-b demo demo-stop seed-media logs push-bridge privacy-check

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

UI_TEST_CLASSES := SignUpFlowUITests OnboardingUITests PeopleUITests FollowingUITests FeedUITests StoriesUITests MessagingUITests NotificationsUITests

ios-ui-test: ios-project sims ## Run the iOS UI scenario tests on simulator A, resetting demo data before each class
	cd $(IOS_DIR) && xcodebuild -project Connectcha.xcodeproj -scheme Connectcha \
	  -destination "platform=iOS Simulator,id=$$(./../scripts/sim-id.sh '$(SIM_A_NAME)')" \
	  -derivedDataPath $(DERIVED) build-for-testing 2>&1 | xcbeautify --quiet
	@failed=0; for c in $(UI_TEST_CLASSES); do \
	  echo "▶ $$c (fresh demo data)"; \
	  $(MAKE) --no-print-directory reset >/dev/null; \
	  psql $(DB_URL) -At -q -c "select tests.create_user('demo_nia','15550000008','Nia','Newcomer');" >/dev/null; \
	  ( cd $(IOS_DIR) && xcodebuild -project Connectcha.xcodeproj -scheme Connectcha \
	    -destination "platform=iOS Simulator,id=$$(./../scripts/sim-id.sh '$(SIM_A_NAME)')" \
	    -derivedDataPath $(DERIVED) -only-testing:ConnectchaUITests/$$c \
	    test-without-building > $(DERIVED)/ui-$$c.log 2>&1 ); status=$$?; \
	  grep -E "✖|❌|error:|Executed [0-9]+ tests?, with" $(DERIVED)/ui-$$c.log | awk '!seen[$$0]++' | head -6; \
	  if [ $$status -ne 0 ]; then failed=1; echo "✖ $$c failed (full log: $(DERIVED)/ui-$$c.log)"; fi; \
	done; \
	if [ $$failed -ne 0 ]; then echo "UI tests: some classes failed"; exit 1; fi; echo "UI tests: all classes passed"

ios-test: ios-project sims ## Run the iOS unit tests on simulator A
	cd $(IOS_DIR) && xcodebuild -project Connectcha.xcodeproj -scheme Connectcha \
	  -destination "platform=iOS Simulator,id=$$(./../scripts/sim-id.sh '$(SIM_A_NAME)')" \
	  -derivedDataPath $(DERIVED) -only-testing:ConnectchaTests \
	  test > $(DERIVED)/unit.log 2>&1; status=$$?; \
	xcbeautify --quiet < $(DERIVED)/unit.log; \
	grep -E "Executed [0-9]+ tests?, with" $(DERIVED)/unit.log | tail -1; \
	if [ $$status -ne 0 ]; then echo "✖ unit tests failed (full log: $(DERIVED)/unit.log)"; exit 1; fi

# ----------------------------------------------------------------------------
# Demo
# ----------------------------------------------------------------------------
sims: ## Create the two demo simulators if they don't exist
	@./scripts/ensure-sim.sh '$(SIM_A_NAME)' 'iPhone 17 Pro' '$(SIM_RUNTIME)'
	@./scripts/ensure-sim.sh '$(SIM_B_NAME)' 'iPhone 17' '$(SIM_RUNTIME)'

demo: ## Start everything: stack, reset+seed, build, two simulators signed in (A=Josh, B=Ana), web page, push bridge
	./scripts/demo.sh

demo-stop: ## Shut down simulators, web page and push bridge (leaves the stack running)
	./scripts/demo.sh stop

push-bridge: ## Deliver stubbed pushes to the simulators (runs until Ctrl-C)
	./scripts/push-bridge.sh

privacy-check: ## Prove a submitted contact hash appears in no server log or table
	./scripts/privacy-log-check.sh
