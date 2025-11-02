SHELL := bash

# Read PROJECT_NAME from .project-name if it exists and not overridden
PROJECT_NAME_FILE := .project-name
ifeq ($(origin PROJECT_NAME), undefined)
  ifneq ($(wildcard $(PROJECT_NAME_FILE)),)
    PROJECT_NAME := $(shell cat $(PROJECT_NAME_FILE))
  else
    PROJECT_NAME := myproj
  endif
endif

BUILD_DIR    := build
XPR_PATH     := $(BUILD_DIR)/$(PROJECT_NAME).xpr

SCRIPTS_DIR  := scripts
SETUP        := $(SCRIPTS_DIR)/setup_build.sh
NORMALIZE    := $(SCRIPTS_DIR)/normalize_xpr.sh
HOOKS        := $(SCRIPTS_DIR)/install_git_hooks.sh

.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "Targets:"
	@echo "  make all                # Install git hooks and create build/ with symlinks"
	@echo "  make build              # Create build/ and create symlinks $(PROJECT_NAME).srcs and .xpr"
	@echo "  make normalize          # Normalize absolute paths in the xpr (also done automatically before commit)"
	@echo "  make hooks              # Install git pre-commit hook"
	@echo "  make clean              # Remove build/ directory"
	@echo
	@echo "Vars:"
	@echo "  PROJECT_NAME=$(PROJECT_NAME) (from .project-name or default)"
	@echo "  Override via: make build PROJECT_NAME=newname (will update .project-name)"

.PHONY: build
build:
	@bash "$(SETUP)" "$(PROJECT_NAME)"

.PHONY: normalize
normalize:
	@bash "$(NORMALIZE)" "PROJECT_NAME.xpr"

.PHONY: hooks
hooks:
	@bash "$(HOOKS)"

.PHONY: clean
clean:
	@rm -rf "$(BUILD_DIR)"
	@echo "Cleaned build directory: $(BUILD_DIR)"

all: hooks build