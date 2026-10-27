// Real Wine lifecycle checks. This executable runs on a native Linux worker.
#include "wine/runtime/json.h"

#include <dirent.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace fs = std::filesystem;
using namespace std::chrono_literals;

namespace {
std::string path_string(const fs::path &path) {
  return path.u8string();
}
std::string read(const fs::path &file) {
  std::ifstream in(file, std::ios::binary);
  if (!in) {
    throw std::runtime_error("cannot read " + path_string(file));
  }
  return {std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>()};
}
void write(const fs::path &file, const std::string &data) {
  std::ofstream out(file, std::ios::binary);
  if (!out || !(out << data)) {
    throw std::runtime_error("cannot write " + path_string(file));
  }
}
std::string quote(const std::string &value) {
  std::string result = "\"";
  for (char c : value) {
    switch (c) {
    case '"':
      result += "\\\"";
      break;
    case '\\':
      result += "\\\\";
      break;
    case '\n':
      result += "\\n";
      break;
    default:
      result += c;
    }
  }
  return result + '"';
}
struct Config {
  fs::path launcher, loader, server, payload, wrong_arch, companion;
  bool payload_layout = false;
};
std::string field(const wine::Json &json, const std::string &name) {
  return json.at(name).as_string();
}
Config config(const std::string &data) {
  wine::Json value = wine::JsonParser(data).parse();
  fs::path root =
      fs::u8path(std::getenv("TEST_SRCDIR") ? std::getenv("TEST_SRCDIR") : "");
  auto locate = [&](const char *name) {
    return root / fs::u8path(field(value, name));
  };
  Config c{locate("Launcher"), locate("Loader"),    locate("Server"),
           locate("Payload"),  locate("WrongArch"), locate("Companion")};
  c.payload_layout = value.at("PayloadLayout").as_bool();
  return c;
}
struct Process {
  pid_t pid;
  fs::path log;
};
Process launch(const fs::path &program, const std::vector<std::string> &args,
               const fs::path &log,
               const std::map<std::string, std::string> &env = {}) {
  pid_t pid = fork();
  if (pid == 0) {
    FILE *output = std::fopen(log.c_str(), "wb");
    if (output) {
      dup2(fileno(output), 1);
      dup2(fileno(output), 2);
      std::fclose(output);
    }
    setenv("XML_OUTPUT_FILE", "", 1);
    setenv("TEST_SHARD_STATUS_FILE", "", 1);
    for (const auto &[key, value] : env) {
      setenv(key.c_str(), value.c_str(), 1);
    }
    std::vector<std::string> strings{path_string(program)};
    strings.insert(strings.end(), args.begin(), args.end());
    std::vector<char *> argv;
    for (auto &item : strings) {
      argv.push_back(item.data());
    }
    argv.push_back(nullptr);
    execv(strings.front().c_str(), argv.data());
    _exit(127);
  }
  if (pid < 0) {
    throw std::runtime_error("fork failed");
  }
  return {pid, log};
}
int wait(const Process &process, std::chrono::seconds timeout = 75s) {
  auto deadline = std::chrono::steady_clock::now() + timeout;
  int status = 0;
  while (waitpid(process.pid, &status, WNOHANG) == 0) {
    if (std::chrono::steady_clock::now() > deadline) {
      kill(process.pid, SIGKILL);
      waitpid(process.pid, &status, 0);
      throw std::runtime_error("supervisor timeout: " + read(process.log));
    }
    std::this_thread::sleep_for(20ms);
  }
  return WIFEXITED(status)     ? WEXITSTATUS(status)
         : WIFSIGNALED(status) ? 128 + WTERMSIG(status)
                               : 125;
}
void require(bool condition, const std::string &message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}
void wait_file(const fs::path &file, const std::vector<fs::path> &logs) {
  auto deadline = std::chrono::steady_clock::now() + 75s;
  while (!fs::exists(file) && std::chrono::steady_clock::now() < deadline) {
    std::this_thread::sleep_for(50ms);
  }
  if (!fs::exists(file)) {
    std::string message = "fixture output missing: " + path_string(file);
    for (const auto &log : logs) {
      message += "\n" + read(log);
    }
    throw std::runtime_error(message);
  }
}
wine::Json record(const fs::path &file) {
  return wine::JsonParser(read(file)).parse();
}
std::string output_arg(const fs::path &file) {
  return "{windows_path:" + quote(path_string(file)) + "}";
}
std::string runtime_config(const Config &c, const fs::path &payload,
                           bool runfiles = false,
                           const std::string &declared_guest = "") {
  return "{\"supported_guest_cpus\":[\"x86_64\"],\"loader\":" +
         quote(path_string(c.loader)) +
         ",\"server\":" + quote(path_string(c.server)) +
         ",\"payload\":" + quote(path_string(payload)) +
         ",\"runfiles\":" + (runfiles ? "true" : "false") +
         ",\"declared_guest_cpu\":" + quote(declared_guest) + "}";
}
fs::path scratch() {
  std::string pattern =
      std::string(std::getenv("TEST_TMPDIR") ? std::getenv("TEST_TMPDIR")
                                             : "/tmp") +
      "/contract-XXXXXX";
  std::vector<char> chars(pattern.begin(), pattern.end());
  chars.push_back(0);
  if (!mkdtemp(chars.data())) {
    throw std::runtime_error("cannot create test scratch");
  }
  return fs::u8path(chars.data());
}
void verify_layout(const Config &c, const fs::path &dir) {
  for (auto name : {"source", "generated", "logical"}) {
    fs::create_directory(dir / name);
  }
  fs::copy_file(c.payload, dir / "source/app.exe");
  fs::copy_file(c.companion, dir / "generated/companion.dll");
  fs::create_symlink("../source/app.exe", dir / "logical/app.exe");
  fs::create_symlink("../generated/companion.dll",
                     dir / "logical/companion.dll");
  fs::path output = dir / "layout.json";
  fs::path config_file = dir / "layout.config.json";
  write(config_file, runtime_config(c, dir / "logical/app.exe"));
  Process process = launch(c.launcher,
                           {"--config", path_string(config_file), "--", "--dll",
                            "--output", output_arg(output)},
                           dir / "layout.log");
  require(wait(process) == 0,
          "logical payload/DLL adjacency: " + read(process.log));
  require(field(record(output), "child") == "child-ok",
          "logical payload child did not execute");
  write(dir / "MANIFEST",
        "logical/app.exe " + path_string(dir / "source/app.exe") + "\n");
  write(config_file, runtime_config(c, "logical/app.exe", true));
  fs::remove(output);
  process = launch(c.launcher,
                   {"--config", path_string(config_file), "--", "--dll",
                    "--output", output_arg(output)},
                   dir / "runfiles-layout.log",
                   {{"RUNFILES_DIR", path_string(dir)},
                    {"RUNFILES_MANIFEST_FILE", path_string(dir / "MANIFEST")}});
  require(wait(process) == 0,
          "runfiles payload/DLL adjacency: " + read(process.log));
  require(field(record(output), "child") == "child-ok",
          "runfiles payload child did not execute");
  std::cout << "PASS: symlinked payload loads adjacent DLL\n";
}
bool owned_descendant(const std::string &prefix) {
  DIR *proc = opendir("/proc");
  if (!proc) {
    return false;
  }
  bool found = false;
  while (dirent *entry = readdir(proc)) {
    if (entry->d_name[0] < '0' || entry->d_name[0] > '9') {
      continue;
    }
    std::ifstream input(std::string("/proc/") + entry->d_name + "/environ",
                        std::ios::binary);
    std::string data{std::istreambuf_iterator<char>(input),
                     std::istreambuf_iterator<char>()};
    if (data.find("WINEPREFIX=" + prefix + '\0') != std::string::npos) {
      found = true;
      break;
    }
  }
  closedir(proc);
  return found;
}
void verify_lifecycle(const Config &c, const fs::path &dir) {
  std::string original_payload = read(c.payload),
              original_loader = read(c.loader);
  int count = 0;
  auto start = [&](const fs::path &payload,
                   const std::vector<std::string> &args) {
    fs::path config_file =
        dir / ("invocation-" + std::to_string(++count) + ".json");
    write(config_file, runtime_config(c, payload));
    std::vector<std::string> invocation{"--config", path_string(config_file),
                                        "--"};
    invocation.insert(invocation.end(), args.begin(), args.end());
    return launch(c.launcher, invocation,
                  dir / ("invocation-" + std::to_string(count) + ".log"));
  };
  fs::path first_out = dir / "first.json", second_out = dir / "second.json";
  Process first = start(
      c.payload, {"--output", output_arg(first_out), "--isolated", "--hold"});
  Process second = start(
      c.payload, {"--output", output_arg(second_out), "--isolated", "--hold"});
  wait_file(first_out, {first.log, second.log});
  wait_file(second_out, {first.log, second.log});
  wine::Json one = record(first_out), two = record(second_out);
  std::string prefix1 = field(one.at("env"), "WINEPREFIX"),
              prefix2 = field(two.at("env"), "WINEPREFIX");
  require(!prefix1.empty() && !prefix2.empty() && prefix1 != prefix2 &&
              field(one, "child") == "child-ok" &&
              field(two, "child") == "child-ok",
          "private prefix/child contract");
  auto cancel = [&](const Process &process, const std::string &prefix) {
    kill(process.pid, SIGTERM);
    require(wait(process, 15s) != 0, "cancellation unexpectedly succeeded");
    require(!fs::exists(fs::path(prefix).parent_path()),
            "scratch not cleaned: " + prefix + "\n" + read(process.log));
    require(!owned_descendant(prefix), "owned descendant survived");
  };
  cancel(first, prefix1);
  require(kill(second.pid, 0) == 0,
          "first cancellation killed second invocation");
  cancel(second, prefix2);
  Process exit = start(c.payload, {"--exit", "37"});
  require(wait(exit) == 37, "exit-code contract: " + read(exit.log));
  Process wrong_arch = start(c.wrong_arch, {});
  require(wait(wrong_arch) == 125 &&
              read(wrong_arch.log).find("unsupported by this Wine runtime") !=
                  std::string::npos,
          "wrong payload CPU rejection");
  auto reject = [&](const std::string &name, const std::string &configuration,
                    const std::string &expected) {
    fs::path file = dir / (name + ".json");
    write(file, configuration);
    auto process = launch(c.launcher, {"--config", path_string(file), "--"},
                          dir / (name + ".log"));
    require(wait(process) == 125 &&
                read(process.log).find(expected) != std::string::npos,
            name + " rejection: " + read(process.log));
  };
  reject("declared-mismatch", runtime_config(c, c.payload, false, "aarch64"),
         "does not match declared guest aarch64");
  std::string i386 = original_payload;
  auto byte = [&](size_t offset) {
    return static_cast<unsigned char>(i386.at(offset));
  };
  size_t pe = byte(60) | (byte(61) << 8) | (byte(62) << 16) | (byte(63) << 24);
  i386.at(pe + 4) = 0x4c;
  i386.at(pe + 5) = 0x01;
  write(dir / "i386.exe", i386);
  reject("i386", runtime_config(c, dir / "i386.exe"),
         "unsupported payload PE machine 332");
  write(dir / "not-pe.exe", "this is not a PE file");
  reject("not-pe", runtime_config(c, dir / "not-pe.exe"),
         "not a Windows PE executable");
  Config wrong_loader = c;
  fs::path wrong_loader_file = dir / "wrong-loader.elf";
  std::string wrong_loader_bytes(64, '\0');
  wrong_loader_bytes.replace(0, 4,
                             "\x7f"
                             "ELF",
                             4);
  wrong_loader_bytes[4] = 2;                       // ELFCLASS64
  wrong_loader_bytes[5] = 1;                       // little endian
  wrong_loader_bytes[18] = static_cast<char>(183); // AArch64 e_machine
  write(wrong_loader_file, wrong_loader_bytes);
  wrong_loader.loader = wrong_loader_file;
  fs::path config_file = dir / "wrong-loader.json";
  write(config_file, runtime_config(wrong_loader, c.payload));
  Process mismatch =
      launch(c.launcher, {"--config", path_string(config_file), "--"},
             dir / "wrong-loader.log");
  require(wait(mismatch) == 125 &&
              read(mismatch.log).find("Wine executable CPU does not match") !=
                  std::string::npos,
          "wrong loader CPU rejection");
  require(read(c.payload) == original_payload &&
              read(c.loader) == original_loader,
          "declared inputs were modified");
  std::cout << "PASS: isolation, cancellation, children, status, architecture, "
               "immutable inputs\n";
}
} // namespace

int main(int, char **argv) {
  try {
    Config c = config(read(std::string(argv[0]) + ".json"));
    fs::path dir = scratch();
    try {
      if (c.payload_layout) {
        verify_layout(c, dir);
      } else {
        verify_lifecycle(c, dir);
      }
    } catch (...) {
      fs::remove_all(dir);
      throw;
    }
    fs::remove_all(dir);
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "verify: " << error.what() << '\n';
    return 1;
  }
}
