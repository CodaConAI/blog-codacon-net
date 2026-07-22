# CODACON Blog

Source for the [CODACON](https://codacon.net) blog. Posts are written in Markdown under `/posts` and compiled into `blog.html`.

## Licensing

Code in this repository is licensed under **Apache-2.0** ([LICENSE](LICENSE)). Content under `/posts` is licensed under **CC BY 4.0** ([LICENSE-CONTENT](LICENSE-CONTENT)).

See [NOTICE](NOTICE) for attribution requirements.

## Building

Run the build script to compile all Markdown posts into `blog.html`:

```bash
./build.sh
```

Posts are rendered in reverse chronological order. The output includes Schema.org metadata, OpenGraph tags, and semantic HTML for search engines and LLM discoverability.

## Adding a Post

Create a new Markdown file in `/posts` with this front matter:

```yaml
---
title: "Your Post Title"
date: 2026-07-22
author: David — CODACON Inc.
description: "A short summary for metadata and previews."
license: CC-BY-4.0
SPDX-License-Identifier: CC-BY-4.0
---
```

Then run `./build.sh` to regenerate `blog.html`.

## Citation

GitHub renders a "Cite this repository" button from [CITATION.cff](CITATION.cff).
