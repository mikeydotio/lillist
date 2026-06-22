# Third-Party Licenses

Lillist is licensed under the [MIT License](LICENSE). It bundles or builds
against the third-party components below. All are permissive licenses
(MIT, Apache-2.0, BSD-3-Clause, SIL OFL-1.1); none is copyleft and none
requires Lillist itself to change its license. This file preserves the
attribution those licenses require.

## Components

| Component | Version | License | Distributed in product? |
| --- | --- | --- | --- |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | 1.7.1 | Apache-2.0 (with Swift runtime exception) | Yes — the `lillist` CLI |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | 2.9.3 | BSD-3-Clause | Yes — the macOS app (auto-update) |
| [Plus Jakarta Sans](https://github.com/tokotype/PlusJakartaSans) | bundled | SIL OFL-1.1 | Yes — bundled font |
| [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | 1.19.2 | MIT | No — test only |
| [swift-custom-dump](https://github.com/pointfreeco/swift-custom-dump) | 1.5.0 | MIT | No — test only (transitive) |
| [xctest-dynamic-overlay](https://github.com/pointfreeco/xctest-dynamic-overlay) | 1.9.0 | MIT | No — test only (transitive) |
| [swift-syntax](https://github.com/swiftlang/swift-syntax) | 603.0.1 | Apache-2.0 | No — test/build only (transitive) |

The bundled font ships with its full license alongside the font files at
`Packages/LillistUI/Sources/LillistUI/Resources/Fonts/OFL.txt`. "Plus
Jakarta Sans" and "Plus Jakarta" are Reserved Font Names under the OFL;
the font may be bundled and redistributed with this software but may not
be sold by itself.

---

## License texts

### MIT License

Applies to: swift-snapshot-testing (Copyright (c) 2019 Point-Free, Inc.),
swift-custom-dump (Copyright (c) 2021 Point-Free, Inc.),
xctest-dynamic-overlay (Copyright (c) 2021 Point-Free, Inc.).

```
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Apache License 2.0

Applies to: swift-argument-parser and swift-syntax (Copyright Apple Inc. and
the Swift project authors). swift-argument-parser additionally carries the
Swift runtime library exception. The full license is available at
<https://www.apache.org/licenses/LICENSE-2.0>; per Section 4 the NOTICE and
copyright attribution are preserved here.

> Licensed under the Apache License, Version 2.0 (the "License"); you may not
> use these files except in compliance with the License. You may obtain a copy
> of the License at https://www.apache.org/licenses/LICENSE-2.0. Unless
> required by applicable law or agreed to in writing, software distributed
> under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
> CONDITIONS OF ANY KIND, either express or implied.

### BSD 3-Clause License

Applies to: Sparkle (Copyright (c) 2006-2013 Andy Matuschak; Copyright (c)
2009-2013 Elgato Systems GmbH; Copyright (c) 2011-2014 Kornel Lesiński;
and contributors).

```
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES ARE DISCLAIMED. IN NO EVENT SHALL THE
COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES ARISING IN ANY WAY
OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
DAMAGE.
```

### SIL Open Font License 1.1

Applies to: Plus Jakarta Sans (Copyright 2020 The Plus Jakarta Sans Project
Authors). Full text:
`Packages/LillistUI/Sources/LillistUI/Resources/Fonts/OFL.txt`.
