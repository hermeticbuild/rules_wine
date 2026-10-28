// Assert observable records written by independent Windows fixture processes.
#include "nlohmann/json.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;

nlohmann::json read(const fs::path &path) {
  std::ifstream in(path);
  if (!in) {
    throw std::runtime_error("cannot read " + path.string());
  }
  std::string data{std::istreambuf_iterator<char>(in),
                   std::istreambuf_iterator<char>()};
  return nlohmann::json::parse(data);
}

int main(int argc, char **argv) {
  try {
    if (argc != 1) {
      throw std::runtime_error("unexpected verifier arguments");
    }
    auto config = read(std::string(argv[0]) + ".json");
    for (const auto &[file, expected] : config.items()) {
      auto record = read(fs::path(std::getenv("TEST_SRCDIR")) / file);
      std::vector<std::string> actual;
      const auto args = record.at("args").get<std::vector<std::string>>();
      for (size_t i = 0; i < args.size(); ++i) {
        if (args[i] == "--output") {
          ++i;
        } else {
          actual.push_back(args[i]);
        }
      }
      if (actual.size() != expected.size()) {
        throw std::runtime_error(file + ": argv cardinality " +
                                 std::to_string(actual.size()) +
                                 " != " + std::to_string(expected.size()));
      }
      for (size_t i = 0; i < actual.size(); ++i) {
        if (actual[i] != expected.at(i).get<std::string>()) {
          throw std::runtime_error(file + ": unexpected argv[" +
                                   std::to_string(i) + "] = " + actual[i]);
        }
      }
      if (record.contains("child") && !record.at("child").is_null() &&
          record.at("child").get<std::string>() != "child-ok") {
        throw std::runtime_error(file + ": child process failed");
      }
      std::cout << "PASS: " << file << '\n';
    }
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
