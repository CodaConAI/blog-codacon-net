#!/usr/bin/env bash
set -euo pipefail

POSTS_DIR="posts"
OUTPUT="blog.html"
SITE_URL="https://codacon.net"
SITE_NAME="CODACON"
SOURCE_REPO="https://github.com/CodaConAI/blog-codacon-net"

parse_front_matter() {
    local file="$1"
    local key="$2"
    sed -n '/^---$/,/^---$/p' "$file" | grep "^${key}:" | head -1 | sed "s/^${key}:[[:space:]]*//" | sed 's/^"\(.*\)"$/\1/'
}

inline_format() {
    local line="$1"
    line=$(echo "$line" | sed 's/\*\*\([^*]*\)\*\*/<strong>\1<\/strong>/g')
    line=$(echo "$line" | sed 's/\*\([^*]*\)\*/<em>\1<\/em>/g')
    line=$(echo "$line" | sed 's/`\([^`]*\)`/<code>\1<\/code>/g')
    line=$(echo "$line" | sed 's/\[\([^]]*\)\](\([^)]*\))/<a href="\2">\1<\/a>/g')
    echo "$line"
}

markdown_to_html() {
    local in_ul=0
    local in_ol=0
    local in_paragraph=0
    local in_code=0
    local in_blockquote=0
    local skip_frontmatter=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip front matter
        if [[ "$line" == "---" ]] && (( ! in_code )); then
            if (( skip_frontmatter == 0 )); then
                skip_frontmatter=1
                while IFS= read -r line; do
                    [[ "$line" == "---" ]] && break
                done
                continue
            fi
        fi

        # Code blocks (fenced with ```)
        if [[ "$line" =~ ^\`\`\` ]]; then
            if (( in_code )); then
                echo "</code></pre>"
                in_code=0
            else
                if (( in_paragraph )); then echo "</p>"; in_paragraph=0; fi
                echo "<pre><code>"
                in_code=1
            fi
            continue
        fi

        if (( in_code )); then
            # HTML-escape inside code blocks
            line="${line//&/&amp;}"
            line="${line//</&lt;}"
            line="${line//>/&gt;}"
            echo "$line"
            continue
        fi

        # Empty line — close open blocks
        if [[ -z "$line" ]]; then
            if (( in_ul )); then echo "</ul>"; in_ul=0; fi
            if (( in_ol )); then echo "</ol>"; in_ol=0; fi
            if (( in_paragraph )); then echo "</p>"; in_paragraph=0; fi
            if (( in_blockquote )); then echo "</blockquote>"; in_blockquote=0; fi
            continue
        fi

        # Headings
        if [[ "$line" =~ ^###[[:space:]]+(.*) ]]; then
            echo "<h3>${BASH_REMATCH[1]}</h3>"
            continue
        fi
        if [[ "$line" =~ ^##[[:space:]]+(.*) ]]; then
            echo "<h2>${BASH_REMATCH[1]}</h2>"
            continue
        fi

        # Blockquotes
        if [[ "$line" =~ ^\>[[:space:]]*(.*) ]]; then
            local bq_content="${BASH_REMATCH[1]}"
            bq_content=$(inline_format "$bq_content")
            if (( ! in_blockquote )); then
                echo "<blockquote>"
                in_blockquote=1
            fi
            echo "<p>${bq_content}</p>"
            continue
        fi

        # Ordered list items
        if [[ "$line" =~ ^[0-9]+\.[[:space:]]+(.*) ]]; then
            if (( ! in_ol )); then
                echo "<ol>"
                in_ol=1
            fi
            local item="${BASH_REMATCH[1]}"
            item=$(inline_format "$item")
            echo "<li>${item}</li>"
            continue
        fi

        # Unordered list items
        if [[ "$line" =~ ^-[[:space:]]+(.*) ]]; then
            if (( ! in_ul )); then
                echo "<ul>"
                in_ul=1
            fi
            local item="${BASH_REMATCH[1]}"
            item=$(inline_format "$item")
            echo "<li>${item}</li>"
            continue
        fi

        # Paragraph text
        if (( ! in_paragraph )); then
            echo -n "<p>"
            in_paragraph=1
        fi

        line=$(inline_format "$line")
        echo "$line"
    done

    if (( in_ul )); then echo "</ul>"; fi
    if (( in_ol )); then echo "</ol>"; fi
    if (( in_paragraph )); then echo "</p>"; fi
    if (( in_blockquote )); then echo "</blockquote>"; fi
    if (( in_code )); then echo "</code></pre>"; fi
}

# Collect posts and sort by date (newest first)
declare -a post_files=()
declare -a post_dates=()

for file in "$POSTS_DIR"/*.md; do
    [[ -f "$file" ]] || continue
    date=$(parse_front_matter "$file" "date")
    post_files+=("$file")
    post_dates+=("$date")
done

# Sort indices by date descending
indices=($(for i in "${!post_dates[@]}"; do echo "$i ${post_dates[$i]}"; done | sort -k2 -r | awk '{print $1}'))

# Build JSON-LD for each post
jsonld_posts=""
for idx in "${indices[@]}"; do
    file="${post_files[$idx]}"
    title=$(parse_front_matter "$file" "title")
    date=$(parse_front_matter "$file" "date")
    description=$(parse_front_matter "$file" "description")
    author=$(parse_front_matter "$file" "author")

    [[ -n "$jsonld_posts" ]] && jsonld_posts+=","
    jsonld_posts+="
    {
      \"@type\": \"BlogPosting\",
      \"headline\": \"${title}\",
      \"datePublished\": \"${date}\",
      \"description\": \"${description}\",
      \"author\": {
        \"@type\": \"Organization\",
        \"name\": \"${author}\",
        \"url\": \"${SITE_URL}\"
      },
      \"publisher\": {
        \"@type\": \"Organization\",
        \"name\": \"${SITE_NAME}\",
        \"url\": \"${SITE_URL}\"
      },
      \"license\": \"https://creativecommons.org/licenses/by/4.0/\",
      \"mainEntityOfPage\": \"${SITE_URL}/blog\"
    }"
done

# Generate article HTML
articles=""
for idx in "${indices[@]}"; do
    file="${post_files[$idx]}"
    title=$(parse_front_matter "$file" "title")
    date=$(parse_front_matter "$file" "date")
    author=$(parse_front_matter "$file" "author")
    license_id=$(parse_front_matter "$file" "SPDX-License-Identifier")
    description=$(parse_front_matter "$file" "description")

    body=$(markdown_to_html < "$file")

    articles+="
    <article itemscope itemtype=\"https://schema.org/BlogPosting\">
      <header>
        <h2 itemprop=\"headline\">${title}</h2>
        <div class=\"meta\">
          <time itemprop=\"datePublished\" datetime=\"${date}\">${date}</time>
          <span itemprop=\"author\">${author}</span>
          <span class=\"license\" title=\"${license_id}\">CC BY 4.0</span>
        </div>
        <p class=\"description\" itemprop=\"description\">${description}</p>
      </header>
      <div itemprop=\"articleBody\">
        ${body}
      </div>
    </article>"
done

cat > "$OUTPUT" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
HTMLEOF

cat >> "$OUTPUT" << HTMLEOF
  <title>${SITE_NAME} Blog</title>
  <meta name="description" content="Insights on AI-powered software engineering and consulting from ${SITE_NAME}.">
  <link rel="canonical" href="${SITE_URL}/blog">

  <meta property="og:type" content="website">
  <meta property="og:site_name" content="${SITE_NAME}">
  <meta property="og:title" content="${SITE_NAME} Blog">
  <meta property="og:description" content="Insights on AI-powered software engineering and consulting from ${SITE_NAME}.">
  <meta property="og:url" content="${SITE_URL}/blog">

  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "Blog",
    "name": "${SITE_NAME} Blog",
    "url": "${SITE_URL}/blog",
    "publisher": {
      "@type": "Organization",
      "name": "${SITE_NAME}",
      "url": "${SITE_URL}"
    },
    "blogPost": [${jsonld_posts}
    ]
  }
  </script>
HTMLEOF

cat >> "$OUTPUT" << 'STYLE'

  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    :root {
      --bg: #E9EAE4;
      --bg-deep: #DFE0D8;
      --ink: #101A2B;
      --ink-secondary: rgba(16, 26, 43, 0.7);
      --prussian: #1B4C7E;
      --verdigris: #3E7C6A;
      --rust: #A2472C;
      --rule: rgba(16, 26, 43, 0.18);
      --code-bg: #101A2B;
      --code-text: #DCE3EC;
    }

    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #0f1117;
        --bg-deep: #1a1d27;
        --ink: #e4e4e7;
        --ink-secondary: rgba(228, 228, 231, 0.65);
        --prussian: #60a5fa;
        --verdigris: #6ee7b7;
        --rust: #f87171;
        --rule: rgba(228, 228, 231, 0.15);
        --code-bg: #1e2028;
        --code-text: #DCE3EC;
      }
    }

    body {
      font-family: Georgia, "Times New Roman", serif;
      background: var(--bg);
      color: var(--ink);
      font-size: 1.0625rem;
      line-height: 1.7;
      max-width: 46rem;
      margin: 0 auto;
      padding: 2rem 1.5rem;
    }

    header.site-header {
      margin-bottom: 3rem;
      padding-bottom: 1rem;
      border-bottom: 2px solid var(--ink);
      display: flex;
      justify-content: space-between;
      align-items: baseline;
      flex-wrap: wrap;
      gap: 0.5rem;
    }

    header.site-header h1 {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      font-size: 1.1rem;
      font-weight: 900;
      letter-spacing: 0.02em;
    }

    header.site-header h1 a { color: var(--ink); text-decoration: none; }

    header.site-header p {
      color: var(--ink-secondary);
      font-family: ui-monospace, "SF Mono", Menlo, monospace;
      font-size: 0.6875rem;
      letter-spacing: 0.09em;
      text-transform: uppercase;
    }

    article {
      margin-bottom: 3.5rem;
      padding-bottom: 3rem;
      border-bottom: 1px solid var(--rule);
    }

    article:last-child { border-bottom: none; }

    article header h2 {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      font-size: 1.75rem;
      font-weight: 900;
      letter-spacing: -0.025em;
      line-height: 1.1;
      margin-bottom: 0.5rem;
    }

    .meta {
      display: flex;
      gap: 1rem;
      color: var(--ink-secondary);
      font-family: ui-monospace, "SF Mono", Menlo, monospace;
      font-size: 0.75rem;
      margin-bottom: 0.5rem;
      flex-wrap: wrap;
    }

    .description {
      color: var(--ink-secondary);
      font-size: 1.1rem;
      line-height: 1.45;
      margin-bottom: 1.5rem;
      font-style: italic;
    }

    .license {
      background: var(--bg-deep);
      padding: 0.1rem 0.5rem;
      border-radius: 3px;
      font-size: 0.6875rem;
      border: 1px solid var(--rule);
    }

    article div[itemprop="articleBody"] p { margin-bottom: 1.35rem; }

    article div[itemprop="articleBody"] h2 {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      font-size: 1.375rem;
      font-weight: 700;
      letter-spacing: -0.01em;
      line-height: 1.25;
      margin: 2.5rem 0 1rem;
      padding-top: 1rem;
      border-top: 1px solid var(--rule);
    }

    article div[itemprop="articleBody"] h3 {
      font-family: ui-monospace, "SF Mono", Menlo, monospace;
      font-size: 0.8125rem;
      font-weight: 700;
      letter-spacing: 0.06em;
      text-transform: uppercase;
      margin: 2rem 0 0.6rem;
    }

    article ul, article ol {
      margin: 0.5rem 0 1.35rem 1.5rem;
    }

    article li { margin-bottom: 0.5rem; }

    a { color: var(--prussian); text-underline-offset: 0.18em; }
    a:hover { text-decoration: underline; }

    pre {
      font-family: ui-monospace, "SF Mono", Menlo, monospace;
      font-size: 0.78125rem;
      line-height: 1.6;
      background: var(--code-bg);
      color: var(--code-text);
      padding: 1.15rem 1.25rem;
      overflow-x: auto;
      margin: 1.5rem 0;
      border-left: 3px solid var(--verdigris);
    }

    code {
      font-family: ui-monospace, "SF Mono", Menlo, monospace;
      font-size: 0.86em;
      background: rgba(27, 76, 126, 0.1);
      padding: 0.1em 0.32em;
      border-radius: 3px;
    }

    @media (prefers-color-scheme: dark) {
      code { background: rgba(96, 165, 250, 0.15); }
    }

    pre code { background: none; padding: 0; font-size: 1em; }

    blockquote {
      border-left: 3px solid var(--rust);
      padding: 1rem 1.15rem;
      margin: 1.5rem 0;
      background: var(--bg-deep);
    }

    blockquote p { margin: 0; }

    strong { font-weight: 600; }

    footer.site-footer {
      margin-top: 2rem;
      padding-top: 1.5rem;
      border-top: 2px solid var(--ink);
      color: var(--ink-secondary);
      font-family: ui-monospace, "SF Mono", Menlo, monospace;
      font-size: 0.6875rem;
      line-height: 1.7;
      text-align: center;
    }

    footer.site-footer a { color: var(--ink-secondary); }

    @media (max-width: 40rem) {
      body { padding: 1rem; }
      article header h2 { font-size: 1.4rem; }
    }
  </style>
</head>
<body>
STYLE

cat >> "$OUTPUT" << HTMLEOF
  <header class="site-header">
    <h1><a href="${SITE_URL}">${SITE_NAME}</a></h1>
    <p>Cloud security &middot; AI engineering &middot; Consulting</p>
  </header>

  <main>
${articles}
  </main>

  <footer class="site-footer">
    <p>&copy; 2026 <a href="${SITE_URL}">${SITE_NAME} Inc.</a> &middot;
    Code: <a href="${SOURCE_REPO}">Apache-2.0</a> &middot;
    Content: <a href="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0</a></p>
  </footer>
</body>
</html>
HTMLEOF

echo "Built ${OUTPUT} with ${#post_files[@]} post(s)."
