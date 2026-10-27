// Linux/macOS Wine supervisor, built from source for the execution platform.
#include "json.h"
#include "rules_cc/cc/runfiles/runfiles.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include <cerrno>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#ifdef __linux__
#include <sys/prctl.h>
#endif

namespace fs = std::filesystem;
using namespace std::chrono_literals;
using rules_cc::cc::runfiles::Runfiles;

namespace {
struct Config {
  std::string arch, loader, server, payload;
  std::map<std::string, std::string> env, runtime_env;
  bool runfiles = false;
};

std::string str(const fs::path &path) {
  return path.u8string();
}
fs::path path(const std::string &value) {
  return fs::u8path(value);
}
std::string read(const fs::path &file) {
  std::ifstream in(file, std::ios::binary);
  if (!in) {
    throw std::runtime_error("cannot open " + str(file));
  }
  return {std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>()};
}
std::string getenv_string(const char *name) {
  const char *value = std::getenv(name);
  return value ? value : "";
}
void replace_all(std::string &value, const std::string &find,
                 const std::string &replacement) {
  if (find.empty()) {
    return;
  }
  for (size_t at = 0; (at = value.find(find, at)) != std::string::npos;
       at += replacement.size()) {
    value.replace(at, find.size(), replacement);
  }
}
std::string absolute_path(const fs::path &value) {
  return str(fs::absolute(value));
}

Config configuration(const std::string &data) {
  wine::Json root = wine::JsonParser(data).parse();
  if (root.kind != wine::Json::object) {
    throw std::runtime_error("expected JSON configuration object");
  }
  Config c;
  c.arch = root.at("arch").as_string();
  c.loader = root.at("loader").as_string();
  c.server = root.at("server").as_string();
  c.payload = root.at("payload").as_string();
  c.runfiles = root.at("runfiles").as_bool();
  auto strings = [](const wine::Json &value) {
    std::map<std::string, std::string> result;
    if (value.kind != wine::Json::null_value &&
        value.kind != wine::Json::object) {
      throw std::runtime_error("expected JSON environment object");
    }
    for (const auto &[key, item] : value.fields) {
      result[key] = item.as_string();
    }
    return result;
  };
  c.env = strings(root.at("env"));
  c.runtime_env = strings(root.at("runtime_env"));
  return c;
}

// Most build actions use only execroot paths. Open runfiles lazily when an
// adapter or explicit runfile argument actually needs them.
class RunfilesContext {
public:
  RunfilesContext(
      std::string self,
      std::string manifest = getenv_string("RUNFILES_MANIFEST_FILE"),
      std::string directory = getenv_string("RUNFILES_DIR"))
      : self_(std::move(self)), manifest_(std::move(manifest)),
        directory_(std::move(directory)) {}

  const Runfiles &get() {
    if (!runfiles_) {
      std::string error;
      // Configuration keys are already canonical runfiles paths, rather than
      // apparent repository names relative to the supervisor's repository.
      runfiles_.reset(
          Runfiles::Create(self_, manifest_, directory_, "", &error));
      if (!runfiles_) {
        throw std::runtime_error(error);
      }
    }
    return *runfiles_;
  }

  std::string resolve(const std::string &logical,
                      bool preserve_layout = false) {
    if (preserve_layout) {
      // DLL lookup follows the executable's directory. Prefer its runfiles
      // location to a manifest entry that points outside that layout.
      for (const auto &[key, value] : get().EnvVars()) {
        if (key == "RUNFILES_DIR" && !value.empty()) {
          auto candidate = path(value) / path(logical);
          if (fs::exists(candidate)) {
            return absolute_path(candidate);
          }
        }
      }
    }
    auto resolved = get().Rlocation(logical);
    if (resolved.empty()) {
      throw std::runtime_error("runfile \"" + logical + "\" not found");
    }
    return absolute_path(path(resolved));
  }

private:
  std::string self_, manifest_, directory_;
  std::unique_ptr<Runfiles> runfiles_;
};

std::string windows_path(const std::string &value) {
  std::string result = "Z:" + absolute_path(path(value));
  std::replace(result.begin(), result.end(), '/', '\\');
  return result;
}
std::string convert(std::string value) {
  constexpr const char *marker = "{windows_path:";
  size_t start = 0;
  while ((start = value.find(marker, start)) != std::string::npos) {
    size_t consumed = 0;
    wine::Json decoded =
        wine::JsonParser(value.substr(start + std::strlen(marker)))
            .parse_prefix(consumed);
    if (decoded.kind != wine::Json::string) {
      throw std::runtime_error(
          "expected JSON string in Windows path interpolation");
    }
    size_t end = start + std::strlen(marker) + consumed;
    if (end == value.size() || value[end] != '}') {
      throw std::runtime_error("unterminated Windows path interpolation");
    }
    std::string converted = windows_path(decoded.as_string());
    value.replace(start, end + 1 - start, converted);
    start += converted.size();
  }
  return value;
}

unsigned little16(const unsigned char *p) {
  return p[0] | (static_cast<unsigned>(p[1]) << 8);
}
unsigned little32(const unsigned char *p) {
  return little16(p) | (little16(p + 2) << 16);
}
#ifdef __APPLE__
unsigned big32(const unsigned char *p) {
  return (static_cast<unsigned>(p[0]) << 24) |
         (static_cast<unsigned>(p[1]) << 16) |
         (static_cast<unsigned>(p[2]) << 8) | p[3];
}
#endif
void validate_pe(const std::string &name) {
  std::ifstream file(path(name), std::ios::binary);
  std::array<unsigned char, 64> header{};
  if (!file.read(reinterpret_cast<char *>(header.data()), header.size()) ||
      header[0] != 'M' || header[1] != 'Z') {
    throw std::runtime_error("payload is not a Windows PE executable");
  }
  file.seekg(little32(header.data() + 60));
  std::array<unsigned char, 4> pe{};
  if (!file.read(reinterpret_cast<char *>(pe.data()), pe.size()) ||
      pe[0] != 'P' || pe[1] != 'E' || pe[2] != 0 || pe[3] != 0) {
    throw std::runtime_error("payload is not a Windows PE executable");
  }
}
void validate_native(const std::string &name, const std::string &arch) {
  std::ifstream file(path(name), std::ios::binary);
  std::array<unsigned char, 64> header{};
  if (!file.read(reinterpret_cast<char *>(header.data()), header.size())) {
    throw std::runtime_error("native Wine executable " + name +
                             ": unreadable header");
  }
#ifdef __linux__
  unsigned want = arch == "aarch64" ? 183 : 62;
  if (header[0] != 0x7f || header[1] != 'E' || header[2] != 'L' ||
      header[3] != 'F' || header[4] != 2 ||
      little16(header.data() + 18) != want) {
    throw std::runtime_error("Wine executable CPU does not match " + arch +
                             ": " + name);
  }
#else
  unsigned want = arch == "aarch64" ? 0x0100000c : 0x01000007;
  unsigned magic = little32(header.data());
  if (magic == 0xfeedfacf && little32(header.data() + 4) == want) {
    return;
  }
  if (big32(header.data()) == 0xcafebabe ||
      big32(header.data()) == 0xcafebabf) {
    bool fat64 = big32(header.data()) == 0xcafebabf;
    unsigned count = big32(header.data() + 4);
    for (unsigned i = 0; i < count && i < 64; ++i) {
      std::array<unsigned char, 32> entry{};
      file.seekg(8 + i * (fat64 ? 32 : 20));
      if (!file.read(reinterpret_cast<char *>(entry.data()), fat64 ? 32 : 20)) {
        break;
      }
      if (big32(entry.data()) == want) {
        return;
      }
    }
  }
  throw std::runtime_error("Wine executable lacks native " + arch +
                           " Mach-O slice (no Rosetta fallback): " + name);
#endif
}

volatile std::sig_atomic_t pending_signal = 0;
void signal_handler(int signum) {
  pending_signal = signum;
}

int execute(const std::string &program, const std::vector<std::string> &args,
            const std::map<std::string, std::string> &env,
            std::chrono::seconds timeout, bool cancellable) {
  pid_t child = fork();
  if (child == 0) {
    setpgid(0, 0);
    for (const auto &[key, value] : env) {
      setenv(key.c_str(), value.c_str(), 1);
    }
    for (int sig : {SIGTERM, SIGINT, SIGHUP}) {
      std::signal(sig, SIG_DFL);
    }
    std::vector<char *> argv{const_cast<char *>(program.c_str())};
    for (const auto &arg : args) {
      argv.push_back(const_cast<char *>(arg.c_str()));
    }
    argv.push_back(nullptr);
    execvp(program.c_str(), argv.data());
    std::fprintf(stderr, "rules_wine: cannot start %s: %s\n", program.c_str(),
                 std::strerror(errno));
    _exit(125);
  }
  if (child < 0) {
    std::perror("rules_wine: fork");
    return 125;
  }
  setpgid(child, child);
  auto deadline = std::chrono::steady_clock::now() + timeout;
  int status = 0;
  for (;;) {
    pid_t waited = waitpid(child, &status, WNOHANG);
    if (waited == child) {
      break;
    }
    if (waited < 0 && errno != EINTR) {
      std::perror("rules_wine: waitpid");
      return 125;
    }
    if (cancellable && pending_signal) {
      int signum = pending_signal;
      kill(-child, SIGKILL);
      waitpid(child, &status, 0);
      return 128 + signum;
    }
    if (timeout.count() && std::chrono::steady_clock::now() >= deadline) {
      std::cerr << "rules_wine: initialization/cleanup timed out\n";
      kill(-child, SIGKILL);
      waitpid(child, &status, 0);
      return 124;
    }
    std::this_thread::sleep_for(20ms);
  }
  if (WIFSIGNALED(status)) {
    return 128 + WTERMSIG(status);
  }
  return WIFEXITED(status) ? WEXITSTATUS(status) : 125;
}

struct Scope {
  std::function<void()> finish;
  ~Scope() {
    if (finish) {
      finish();
    }
  }
};

int invoke(Config c, std::vector<std::string> payload_args,
           const std::string &self) {
#if defined(__x86_64__)
  const std::string cpu = "x86_64";
#elif defined(__aarch64__)
  const std::string cpu = "aarch64";
#else
  const std::string cpu = "unsupported";
#endif
  if (cpu != c.arch) {
    throw std::runtime_error(
        "Wine configuration CPU does not match supervisor " + cpu);
  }
  RunfilesContext runfiles(self);
  auto resolve = [&](const std::string &name, bool canonicalize) {
    if (name.empty()) {
      return name;
    }
    fs::path result = path(c.runfiles ? runfiles.resolve(name, !canonicalize)
                                      : absolute_path(path(name)));
    // Keep the payload's logical runfiles path so adjacent DLL lookup works.
    if (canonicalize) {
      result = fs::canonical(result);
    }
    return str(result);
  };
  c.payload = resolve(c.payload, false);
  c.loader = resolve(c.loader, true);
  c.server = resolve(c.server, true);
  // Wine owns guest CPU support, including any bundled CPU translator.
  validate_pe(c.payload);
  for (auto &arg : payload_args) {
    arg = convert(arg);
  }
  for (auto &[key, value] : c.env) {
    value = convert(value);
  }
  if (c.runfiles) {
    for (const auto &[key, value] : runfiles.get().EnvVars()) {
      c.env.try_emplace(key, value);
    }
  }
  std::signal(SIGTERM, signal_handler);
  std::signal(SIGINT, signal_handler);
  std::signal(SIGHUP, signal_handler);
  validate_native(c.loader, c.arch);
  validate_native(c.server, c.arch);
  std::string scratch_base;
#ifdef __APPLE__
  // Keep Wine's Unix socket path below sockaddr_un's short macOS limit.
  scratch_base = "/tmp";
#else
  scratch_base = getenv_string("TMPDIR");
  if (scratch_base.empty()) {
    scratch_base = "/tmp";
  }
#endif
  std::string template_path = scratch_base + "/rules-wine-XXXXXX";
  std::vector<char> temp(template_path.begin(), template_path.end());
  temp.push_back(0);
  if (!mkdtemp(temp.data())) {
    throw std::runtime_error("cannot create private Wine directory");
  }
  const std::string scratch = temp.data();
  Scope remove{[&] {
    std::error_code error;
    fs::remove_all(path(scratch), error);
    if (error) {
      std::cerr << "rules_wine: cleanup: " << error.message() << '\n';
    }
  }};
  const std::string prefix = scratch + "/prefix";
  const std::map<std::string, std::string> fixed = {
      {"WINEPREFIX", prefix},
      {"WINEARCH", "win64"},
      {"WINELOADER", c.loader},
      {"WINESERVER", c.server},
      {"WINEDLLOVERRIDES", "mscoree,mshtml,winemenubuilder.exe="},
      {"WINEDEBUG", "-all"},
      {"HOME", scratch},
      {"XDG_CACHE_HOME", scratch},
      {"TMPDIR", scratch},
      {"TMP", scratch},
      {"TEMP", scratch},
      {"LC_ALL", "C.UTF-8"},
      {"TZ", "UTC"},
      {"DISPLAY", ""},
      {"WAYLAND_DISPLAY", ""},
      {"PATH", str(path(c.loader).parent_path())},
  };
  for (const auto &[key, value] : fixed) {
    c.env[key] = value;
  }
  for (auto &[key, value] : c.runtime_env) {
    for (const auto &reserved :
         {"WINEPREFIX", "WINEARCH", "WINELOADER", "WINESERVER",
          "WINEDLLOVERRIDES", "HOME", "TMPDIR", "PATH"}) {
      if (key == reserved) {
        throw std::runtime_error("reserved runtime environment " + key);
      }
    }
    replace_all(value, "{loader_dir}", str(path(c.loader).parent_path()));
    replace_all(value, "{server_dir}", str(path(c.server).parent_path()));
    c.env[key] = value;
  }
  for (const char *key :
       {"TEST_TMPDIR", "TEST_UNDECLARED_OUTPUTS_DIR",
        "TEST_UNDECLARED_OUTPUTS_MANIFEST",
        "TEST_UNDECLARED_OUTPUTS_ANNOTATIONS_DIR", "XML_OUTPUT_FILE",
        "TEST_SHARD_STATUS_FILE", "TEST_SRCDIR", "RUNFILES_DIR",
        "RUNFILES_MANIFEST_FILE", "JAVA_RUNFILES"}) {
    std::string value = c.env.count(key) ? c.env[key] : getenv_string(key);
    if (!value.empty()) {
      c.env[key] = windows_path(value);
    }
  }
#ifdef __linux__
  prctl(PR_SET_CHILD_SUBREAPER, 1);
#endif
  Scope stop{[&] {
    if (int status = execute(c.server, {"-k"}, c.env, 5s, false); status) {
      std::cerr << "rules_wine: wineserver cleanup status " << status << '\n';
    }
    execute(c.server, {"-w"}, c.env, 5s, false);
#ifdef __linux__
    int status;
    while (waitpid(-1, &status, WNOHANG) > 0) {
    }
#endif
  }};
  int status = execute(c.loader, {"wineboot.exe", "--init"}, c.env, 60s, true);
  if (status) {
    return status;
  }
  std::vector<std::string> args{windows_path(c.payload)};
  args.insert(args.end(), payload_args.begin(), payload_args.end());
  return execute(c.loader, args, c.env, 0s, true);
}
} // namespace

int main(int argc, char **argv) {
  try {
    if (argc < 4 || std::string(argv[1]) != "--config" ||
        std::string(argv[3]) != "--") {
      throw std::runtime_error(
          "usage: supervisor --config FILE -- [PAYLOAD_ARGS...]");
    }
    std::string self = absolute_path(path(argv[0]));
    std::string config = argv[2];
    int first = 4;
    std::vector<std::string> extra;
    for (int i = first; i < argc; ++i) {
      extra.emplace_back(argv[i]);
    }
    return invoke(configuration(read(path(config))), extra, self);
  } catch (const std::exception &error) {
    std::cerr << "rules_wine: " << error.what() << '\n';
    return 125;
  }
}
