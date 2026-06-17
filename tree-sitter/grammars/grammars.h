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
const TSLanguage *tree_sitter_c(void);
const TSLanguage *tree_sitter_cpp(void);
const TSLanguage *tree_sitter_javascript(void);
const TSLanguage *tree_sitter_typescript(void);
const TSLanguage *tree_sitter_go(void);
const TSLanguage *tree_sitter_rust(void);
const TSLanguage *tree_sitter_java(void);

#ifdef __cplusplus
}
#endif

#endif
