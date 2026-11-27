#include <cstdint>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "converter/converter.h"
#include "converter/immutable_converter.h"
#include "converter/segments.h"
#include "data_manager/data_manager.h"
#include "dictionary/dictionary_interface.h"
#include "engine/modules.h"
#include "prediction/predictor_interface.h"
#include "protocol/commands.pb.h"
#include "protocol/config.pb.h"
#include "request/conversion_request.h"
#include "rewriter/rewriter_interface.h"

namespace {

class EmptyUserDictionary final : public mozc::dictionary::UserDictionaryInterface {
 public:
  void WaitForReloader() override {}
  std::vector<std::string> GetPosList() const override { return {}; }
  bool Load(const mozc::user_dictionary::UserDictionaryStorage&) override { return false; }
  bool IsSuppressedEntry(absl::string_view, absl::string_view) const override { return false; }
  bool HasSuppressedEntries() const override { return false; }
};

class NoPrediction final : public mozc::prediction::PredictorInterface {
 public:
  std::vector<mozc::prediction::Result> Predict(const mozc::ConversionRequest&) const override {
    return {};
  }
  absl::string_view GetPredictorName() const override { return "NoPrediction"; }
};

class NoRewriting final : public mozc::RewriterInterface {
 public:
  bool Rewrite(const mozc::ConversionRequest&, mozc::Segments*) const override { return true; }
};

void WriteJSONString(std::ostream& output, std::string_view value) {
  output.put('"');
  constexpr char digits[] = "0123456789abcdef";
  for (unsigned char byte : value) {
    if (byte == '"' || byte == '\\') {
      output.put('\\');
      output.put(byte);
    } else if (byte < 0x20) {
      output << "\\u00" << digits[byte >> 4] << digits[byte & 15];
    } else {
      output.put(byte);
    }
  }
  output.put('"');
}

void WriteSegments(const mozc::Segments& segments) {
  std::cout.put('[');
  bool first_segment = true;
  for (const auto& segment : segments.conversion_segments()) {
    if (!first_segment) std::cout.put(',');
    first_segment = false;
    std::cout << "{\"reading\":";
    WriteJSONString(std::cout, segment.key());
    std::cout << ",\"candidates\":[";
    for (int index = 0; index < segment.candidates_size(); ++index) {
      if (index != 0) std::cout.put(',');
      WriteJSONString(std::cout, segment.candidate(index).value);
    }
    std::cout << "]}";
  }
  std::cout << "]\n" << std::flush;
}

bool ParseLengths(const std::string& line, std::vector<uint8_t>* lengths) {
  std::istringstream fields(line);
  while (fields >> std::ws, !fields.eof()) {
    int length;
    if (!(fields >> length) || length < 1 || length > 255 || lengths->size() == 256) {
      return false;
    }
    lengths->push_back(static_cast<uint8_t>(length));
  }
  return true;
}

bool Convert(const mozc::converter::Converter& converter, const std::string& reading,
             const std::string& sizes, mozc::Segments* segments) {
  std::vector<uint8_t> lengths;
  if (reading.empty() || reading.size() > 1024 || !ParseLengths(sizes, &lengths)) {
    return false;
  }

  mozc::config::Config config;
  config.set_history_learning_level(mozc::config::Config::NO_HISTORY);
  mozc::commands::Request client;
  mozc::ConversionRequest::Options options;
  options.request_type = mozc::ConversionRequest::CONVERSION;
  options.max_conversion_candidates_size = 200;
  options.enable_user_history_for_conversion = false;
  const auto request = mozc::ConversionRequestBuilder()
                           .SetRequestView(client)
                           .SetConfigView(config)
                           .SetOptions(options)
                           .SetKey(reading)
                           .Build();
  if (!converter.StartConversion(request, segments)) return false;
  return lengths.empty() || converter.ResizeSegments(segments, request, 0, lengths);
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) return 2;
  auto data = mozc::DataManager::CreateFromFile(argv[1]);
  if (!data.ok()) return 2;
  mozc::engine::ModulesPresetBuilder builder;
  auto modules = builder.PresetUserDictionary(std::make_unique<EmptyUserDictionary>())
                     .Build(*std::move(data));
  if (!modules.ok()) return 2;

  mozc::converter::Converter converter(
      *std::move(modules),
      [](const auto& modules) { return std::make_unique<mozc::ImmutableConverter>(modules); },
      [](const auto&, const auto&, const auto&) { return std::make_unique<NoPrediction>(); },
      [](const auto&) { return std::make_unique<NoRewriting>(); });

  std::string reading;
  std::string sizes;
  while (std::getline(std::cin, reading) && std::getline(std::cin, sizes)) {
    mozc::Segments segments;
    if (Convert(converter, reading, sizes, &segments)) {
      WriteSegments(segments);
    } else {
      std::cout << "null\n" << std::flush;
    }
  }
}
