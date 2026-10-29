// Assert observable records written by independent Windows fixture processes.
#include "nlohmann/json.hpp"

#include <algorithm>
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

void require(bool condition, const std::string &message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

void verify_mapping(const nlohmann::json &config) {
  auto load = [&](const std::string &path) {
    return read(fs::path(std::getenv("TEST_SRCDIR")) / path);
  };
  auto mapped = load(config.at("mapped"));
  auto collision = load(config.at("collision"));
  auto param = load(config.at("param"));
  auto contains = [](const nlohmann::json &value, const std::string &part) {
    return value.get<std::string>().find(part) != std::string::npos;
  };
  const bool strip = config.at("mapping");
  require(mapped.at("child") == "child-ok" &&
              mapped.at("args").at(2) == "first",
          "generated input or child execution changed");
  require(mapped.at("env").at("FIXTURE_VALUE") ==
              "space café\nquote\"backslash\\",
          "opaque environment changed");
  require(contains(mapped.at("args").at(1),
                   "\\tests\\mapped_paths\\result café {output}.json") &&
              contains(mapped.at("args").at(3),
                       "/tests/mapping_input/data café {input}.txt"),
          "generated Unicode paths changed");
  require(contains(mapped.at("args").at(1), "\\bazel-out\\cfg\\") == strip &&
              contains(mapped.at("args").at(3), "bazel-out/cfg/") == strip,
          "path mapping mode not observed by payload");
  require(collision.at("child") == "child-ok" &&
              collision.at("args").at(2) == "first" &&
              collision.at("args").at(3) == "second" &&
              !contains(collision.at("args").at(1), "\\bazel-out\\cfg\\") &&
              !contains(collision.at("args").at(4), "bazel-out/cfg/"),
          "mapped collision did not preserve both configurations");
  auto paths = collision.at("args").at(4).get<std::string>();
  require(std::count(paths.begin(), paths.end(), '\n') == 1,
          "collision response file lost an input");
  require(param.at("args").back() == "response one\ncafé" &&
              param.at("env").at("FIXTURE_VALUE") == "opaque/unchanged",
          "parameter file or opaque environment changed");
  for (const auto &path : config.at("distinct")) {
    auto record = load(path);
    auto name = fs::path(path.get<std::string>()).filename().string();
    require(record.at("args").back() == name &&
                record.at("env").at("FIXTURE_VALUE") == name,
            "distinct actions shared invocation state");
  }
}

int main(int argc, char **argv) {
  try {
    if (argc != 1) {
      throw std::runtime_error("unexpected verifier arguments");
    }
    auto config = read(std::string(argv[0]) + ".json");
    if (config.contains("mapping")) {
      verify_mapping(config);
      return 0;
    }
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
