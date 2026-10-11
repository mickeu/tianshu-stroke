// Custom API extension for Hamster iOS
// RimeReplaceInput: replaces a range of the input buffer

#include <rime_api.h>
#include <rime/common.h>
#include <rime/context.h>
#include <rime/service.h>
#include <string>

extern "C" int RimeReplaceInput(uintptr_t session_id, int start, int length, const char* replacement) {
  using namespace rime;
  an<Session> session(Service::instance().GetSession(session_id));
  if (!session)
    return 0;
  Context* ctx = session->context();
  if (!ctx)
    return 0;
  std::string input = ctx->input();
  if (start < 0 || start > (int)input.size())
    return 0;
  if (length < 0 || start + length > (int)input.size())
    length = (int)input.size() - start;
  input.replace(start, length, replacement ? replacement : "");
  ctx->set_input(input);
  return 1;
}
