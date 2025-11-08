# Details

Date : 2025-11-08 17:53:05

Directory /home/winger/zigwk/zbrowser

Total : 61 files,  12989 codes, 3337 comments, 2739 blanks, all 19065 lines

[Summary](results.md) / Details / [Diff Summary](diff.md) / [Diff Details](diff-details.md)

## Files
| filename | language | code | comment | blank | total |
| :--- | :--- | ---: | ---: | ---: | ---: |
| [DESIGN.md](/DESIGN.md) | Markdown | 235 | 671 | 44 | 950 |
| [PLAN.md](/PLAN.md) | Markdown | 290 | 0 | 59 | 349 |
| [README.md](/README.md) | Markdown | 340 | 0 | 89 | 429 |
| [build.zig](/build.zig) | Zig | 283 | 25 | 37 | 345 |
| [docs/API.md](/docs/API.md) | Markdown | 592 | 0 | 153 | 745 |
| [docs/DESIGN.md](/docs/DESIGN.md) | Markdown | 255 | 797 | 44 | 1,096 |
| [docs/LAYOUT_DESIGN.md](/docs/LAYOUT_DESIGN.md) | Markdown | 877 | 0 | 205 | 1,082 |
| [docs/PLAN.md](/docs/PLAN.md) | Markdown | 280 | 0 | 59 | 339 |
| [docs/README.md](/docs/README.md) | Markdown | 222 | 0 | 77 | 299 |
| [env.sh](/env.sh) | Shell Script | 19 | 4 | 1 | 24 |
| [src/css/cascade.zig](/src/css/cascade.zig) | Zig | 111 | 19 | 20 | 150 |
| [src/css/parser.zig](/src/css/parser.zig) | Zig | 450 | 81 | 54 | 585 |
| [src/css/selector.zig](/src/css/selector.zig) | Zig | 191 | 17 | 20 | 228 |
| [src/css/tokenizer.zig](/src/css/tokenizer.zig) | Zig | 406 | 38 | 60 | 504 |
| [src/html/dom.zig](/src/html/dom.zig) | Zig | 326 | 108 | 54 | 488 |
| [src/html/parser.zig](/src/html/parser.zig) | Zig | 423 | 34 | 29 | 486 |
| [src/html/tokenizer.zig](/src/html/tokenizer.zig) | Zig | 317 | 26 | 50 | 393 |
| [src/image/png.zig](/src/image/png.zig) | Zig | 14 | 21 | 5 | 40 |
| [src/layout/block.zig](/src/layout/block.zig) | Zig | 28 | 18 | 10 | 56 |
| [src/layout/box.zig](/src/layout/box.zig) | Zig | 161 | 49 | 36 | 246 |
| [src/layout/context.zig](/src/layout/context.zig) | Zig | 66 | 24 | 18 | 108 |
| [src/layout/engine.zig](/src/layout/engine.zig) | Zig | 82 | 23 | 12 | 117 |
| [src/layout/flexbox.zig](/src/layout/flexbox.zig) | Zig | 54 | 34 | 15 | 103 |
| [src/layout/float.zig](/src/layout/float.zig) | Zig | 59 | 57 | 20 | 136 |
| [src/layout/grid.zig](/src/layout/grid.zig) | Zig | 140 | 35 | 22 | 197 |
| [src/layout/inline.zig](/src/layout/inline.zig) | Zig | 72 | 31 | 18 | 121 |
| [src/layout/position.zig](/src/layout/position.zig) | Zig | 61 | 63 | 11 | 135 |
| [src/layout/style_utils.zig](/src/layout/style_utils.zig) | Zig | 179 | 37 | 27 | 243 |
| [src/main.zig](/src/main.zig) | Zig | 64 | 6 | 14 | 84 |
| [src/render/backend.zig](/src/render/backend.zig) | Zig | 145 | 38 | 41 | 224 |
| [src/render/cpu_backend.zig](/src/render/cpu_backend.zig) | Zig | 271 | 54 | 52 | 377 |
| [src/test/runner.zig](/src/test/runner.zig) | Zig | 141 | 12 | 31 | 184 |
| [src/utils/allocator.zig](/src/utils/allocator.zig) | Zig | 22 | 3 | 6 | 31 |
| [src/utils/math.zig](/src/utils/math.zig) | Zig | 21 | 7 | 7 | 35 |
| [src/utils/string.zig](/src/utils/string.zig) | Zig | 60 | 13 | 15 | 88 |
| [test.zig](/test.zig) | Zig | 58 | 21 | 15 | 94 |
| [tests/MISSING_TESTS.md](/tests/MISSING_TESTS.md) | Markdown | 115 | 167 | 23 | 305 |
| [tests/README.md](/tests/README.md) | Markdown | 102 | 0 | 40 | 142 |
| [tests/css/cascade_test.zig](/tests/css/cascade_test.zig) | Zig | 149 | 18 | 24 | 191 |
| [tests/css/parser_test.zig](/tests/css/parser_test.zig) | Zig | 199 | 7 | 36 | 242 |
| [tests/css/selector_test.zig](/tests/css/selector_test.zig) | Zig | 430 | 55 | 73 | 558 |
| [tests/css/tokenizer_test.zig](/tests/css/tokenizer_test.zig) | Zig | 276 | 2 | 76 | 354 |
| [tests/html/dom_test.zig](/tests/html/dom_test.zig) | Zig | 783 | 80 | 163 | 1,026 |
| [tests/html/parser_test.zig](/tests/html/parser_test.zig) | Zig | 1,020 | 140 | 151 | 1,311 |
| [tests/html/tokenizer_test.zig](/tests/html/tokenizer_test.zig) | Zig | 433 | 38 | 103 | 574 |
| [tests/image/png_test.zig](/tests/image/png_test.zig) | Zig | 7 | 2 | 2 | 11 |
| [tests/layout/block_test.zig](/tests/layout/block_test.zig) | Zig | 157 | 47 | 56 | 260 |
| [tests/layout/box_test.zig](/tests/layout/box_test.zig) | Zig | 184 | 22 | 30 | 236 |
| [tests/layout/context_test.zig](/tests/layout/context_test.zig) | Zig | 215 | 50 | 67 | 332 |
| [tests/layout/engine_test.zig](/tests/layout/engine_test.zig) | Zig | 200 | 96 | 74 | 370 |
| [tests/layout/flexbox_test.zig](/tests/layout/flexbox_test.zig) | Zig | 234 | 44 | 67 | 345 |
| [tests/layout/float_test.zig](/tests/layout/float_test.zig) | Zig | 192 | 40 | 60 | 292 |
| [tests/layout/grid_test.zig](/tests/layout/grid_test.zig) | Zig | 141 | 26 | 42 | 209 |
| [tests/layout/inline_test.zig](/tests/layout/inline_test.zig) | Zig | 187 | 50 | 54 | 291 |
| [tests/layout/position_test.zig](/tests/layout/position_test.zig) | Zig | 140 | 32 | 41 | 213 |
| [tests/render/backend_test.zig](/tests/render/backend_test.zig) | Zig | 7 | 4 | 3 | 14 |
| [tests/render/cpu_backend_test.zig](/tests/render/cpu_backend_test.zig) | Zig | 175 | 23 | 50 | 248 |
| [tests/test_helpers.zig](/tests/test_helpers.zig) | Zig | 89 | 15 | 13 | 117 |
| [tests/utils/allocator_test.zig](/tests/utils/allocator_test.zig) | Zig | 62 | 13 | 24 | 99 |
| [tests/utils/math_test.zig](/tests/utils/math_test.zig) | Zig | 54 | 0 | 10 | 64 |
| [tests/utils/string_test.zig](/tests/utils/string_test.zig) | Zig | 123 | 0 | 27 | 150 |

[Summary](results.md) / Details / [Diff Summary](diff.md) / [Diff Details](diff-details.md)