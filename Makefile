# Makefile for nvim-tester functional testing
.PHONY: test test_file test_here deps clean update_deps

# Download mini.nvim dependency
deps/mini.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/nvim-mini/mini.nvim $@

# Update mini.nvim dependency
update_deps:
	@if [ -d "deps/mini.nvim" ]; then \
		cd deps/mini.nvim && git pull; \
	else \
		$(MAKE) deps; \
	fi

# Run all tests
test: deps/mini.nvim
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

# Run single test file (usage: make test_file FILE=test_go_functional)
test_file: deps/mini.nvim
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('tests/$(FILE).lua')"

# Run test at cursor location (interactive)
test_here:
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_at_location()"

# Clean dependencies
clean:
	rm -rf deps

# Watch mode (requires entr or similar tool)
test_watch: deps/mini.nvim
	ls tests/*.lua lua/tester/*.lua | entr -r make test
