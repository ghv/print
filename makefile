.PHONY: unit build run test rbuild install clean

RELEASE_FLAGS = -c release
EXECUTABLE_PATH = $(shell swift build $(RELEASE_FLAGS) --show-bin-path)/printer
INSTALL_FOLDER = /usr/local/bin

unit:
	swift test

build:
	@echo Building Release...
	swift build $(RELEASE_FLAGS)

install: build
	@echo "Installing print in $(INSTALL_FOLDER)"
	@install $(EXECUTABLE_PATH) $(INSTALL_FOLDER)

clean:
	swift package reset
