CORE := ../../lib/dmxcore/src
CXXFLAGS := -std=c++17 -Wall -Wextra -Werror -I$(CORE)

test: test_core
	./test_core

test_core: test_core.cpp $(CORE)/artnet.cpp $(CORE)/dmx_node.cpp
	$(CXX) $(CXXFLAGS) -o $@ $^

clean:
	rm -f test_core

.PHONY: test clean
