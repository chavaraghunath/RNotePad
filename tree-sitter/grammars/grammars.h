// SPDX-License-Identifier: MIT
// Sourcepad — declarations for every vendored grammar.
// Each tree-sitter grammar exposes a single entry point
// `tree_sitter_<name>()` returning a `const TSLanguage *`.
// We collect them here so the bridging header can pull them in for Swift.

#ifndef SOURCEPAD_TS_GRAMMARS_H
#define SOURCEPAD_TS_GRAMMARS_H

#include "../lib/include/tree_sitter/api.h"

#ifdef __cplusplus
extern "C" {
#endif

const TSLanguage *tree_sitter_python(void);

#ifdef __cplusplus
}
#endif

#endif
