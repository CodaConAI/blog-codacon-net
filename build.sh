#!/usr/bin/env bash
set -euo pipefail

POSTS_DIR="posts"
OUTPUT="blog.html"
SITE_URL="https://codacon.net"
SITE_NAME="CodaCon"

parse_front_matter() {
    local file="$1"
    local key="$2"
    sed -n '/^---$/,/^---$/p' "$file" | grep "^${key}:" | head -1 | sed "s/^${key}:[[:space:]]*//" | sed 's/^"\(.*\)"$/\1/'
}

markdown_to_html() {
    local in_list=0
    local in_paragraph=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip front matter
        if [[ "$line" == "---" ]]; then
            # Read until closing ---
            while IFS= read -r line; do
                [[ "$line" == "---" ]] && break
            done
            continue
        fi

        # Empty line
        if [[ -z "$line" ]]; then
            if (( in_list )); then
                echo "</ul>"
                in_list=0
            fi
            if (( in_paragraph )); then
                echo "</p>"
                in_paragraph=0
            fi
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

        # List items
        if [[ "$line" =~ ^-[[:space:]]+(.*) ]]; then
            if (( ! in_list )); then
                echo "<ul>"
                in_list=1
            fi
            local item="${BASH_REMATCH[1]}"
            item=$(echo "$item" | sed 's/\*\*\([^*]*\)\*\*/<strong>\1<\/strong>/g')
            item=$(echo "$item" | sed 's/\*\([^*]*\)\*/<em>\1<\/em>/g')
            item=$(echo "$item" | sed 's/`\([^`]*\)`/<code>\1<\/code>/g')
            echo "<li>${item}</li>"
            continue
        fi

        # Paragraph text
        if (( ! in_paragraph )); then
            echo -n "<p>"
            in_paragraph=1
        fi

        # Inline formatting
        line=$(echo "$line" | sed 's/\*\*\([^*]*\)\*\*/<strong>\1<\/strong>/g')
        line=$(echo "$line" | sed 's/\*\([^*]*\)\*/<em>\1<\/em>/g')
        line=$(echo "$line" | sed 's/`\([^`]*\)`/<code>\1<\/code>/g')
        # Links: [text](url)
        line=$(echo "$line" | sed 's/\[\([^]]*\)\](\([^)]*\))/<a href="\2">\1<\/a>/g')

        echo "$line"
    done

    if (( in_list )); then echo "</ul>"; fi
    if (( in_paragraph )); then echo "</p>"; fi
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

# Get the first post's info for OpenGraph
first_idx="${indices[0]}"
og_title=$(parse_front_matter "${post_files[$first_idx]}" "title")
og_description=$(parse_front_matter "${post_files[$first_idx]}" "description")

# Generate article HTML
articles=""
for idx in "${indices[@]}"; do
    file="${post_files[$idx]}"
    title=$(parse_front_matter "$file" "title")
    date=$(parse_front_matter "$file" "date")
    author=$(parse_front_matter "$file" "author")
    license_id=$(parse_front_matter "$file" "SPDX-License-Identifier")

    body=$(markdown_to_html < "$file")

    articles+="
    <article itemscope itemtype=\"https://schema.org/BlogPosting\">
      <header>
        <h2 itemprop=\"headline\">${title}</h2>
        <div class=\"meta\">
          <time itemprop=\"datePublished\" datetime=\"${date}\">${date}</time>
          <span itemprop=\"author\" itemscope itemtype=\"https://schema.org/Organization\">
            <span itemprop=\"name\">${author}</span>
          </span>
          <span class=\"license\" title=\"${license_id}\">CC BY 4.0</span>
        </div>
      </header>
      <div itemprop=\"articleBody\">
        ${body}
      </div>
    </article>"
done

# Write the full HTML
cat > "$OUTPUT" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${SITE_NAME} Blog</title>
  <meta name="description" content="Insights on AI-powered software engineering and consulting from CodaCon.">
  <link rel="canonical" href="${SITE_URL}/blog">

  <!-- OpenGraph -->
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="${SITE_NAME}">
  <meta property="og:title" content="${SITE_NAME} Blog">
  <meta property="og:description" content="Insights on AI-powered software engineering and consulting from CodaCon.">
  <meta property="og:url" content="${SITE_URL}/blog">

  <!-- Schema.org JSON-LD -->
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

  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    :root {
      --bg: #ffffff;
      --bg-secondary: #f8f9fa;
      --text: #1a1a1a;
      --text-secondary: #555;
      --accent: #2563eb;
      --border: #e5e7eb;
      --code-bg: #f1f5f9;
      --shadow: 0 1px 3px rgba(0,0,0,0.08);
    }

    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #0f1117;
        --bg-secondary: #1a1d27;
        --text: #e4e4e7;
        --text-secondary: #a1a1aa;
        --accent: #60a5fa;
        --border: #2e3039;
        --code-bg: #1e2028;
        --shadow: 0 1px 3px rgba(0,0,0,0.3);
      }
    }

    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.7;
      max-width: 44rem;
      margin: 0 auto;
      padding: 2rem 1.5rem;
    }

    header.site-header {
      margin-bottom: 3rem;
      padding-bottom: 1.5rem;
      border-bottom: 1px solid var(--border);
    }

    header.site-header h1 {
      font-size: 1.75rem;
      font-weight: 700;
      letter-spacing: -0.025em;
    }

    header.site-header h1 a {
      color: var(--text);
      text-decoration: none;
    }

    header.site-header p {
      color: var(--text-secondary);
      margin-top: 0.25rem;
      font-size: 0.95rem;
    }

    article {
      margin-bottom: 3rem;
      padding-bottom: 2.5rem;
      border-bottom: 1px solid var(--border);
    }

    article:last-child {
      border-bottom: none;
    }

    article header h2 {
      font-size: 1.5rem;
      font-weight: 600;
      letter-spacing: -0.02em;
      margin-bottom: 0.5rem;
    }

    .meta {
      display: flex;
      gap: 1rem;
      color: var(--text-secondary);
      font-size: 0.85rem;
      margin-bottom: 1.5rem;
      flex-wrap: wrap;
    }

    .license {
      background: var(--bg-secondary);
      padding: 0.1rem 0.5rem;
      border-radius: 3px;
      font-size: 0.75rem;
      border: 1px solid var(--border);
    }

    article div[itemprop="articleBody"] p {
      margin-bottom: 1rem;
    }

    article div[itemprop="articleBody"] h2 { font-size: 1.3rem; margin: 1.5rem 0 0.75rem; }
    article div[itemprop="articleBody"] h3 { font-size: 1.1rem; margin: 1.25rem 0 0.5rem; }

    article ul {
      margin: 0.5rem 0 1rem 1.5rem;
    }

    article li {
      margin-bottom: 0.35rem;
    }

    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }

    code {
      background: var(--code-bg);
      padding: 0.15rem 0.35rem;
      border-radius: 3px;
      font-size: 0.9em;
    }

    strong { font-weight: 600; }

    footer.site-footer {
      margin-top: 2rem;
      padding-top: 1.5rem;
      border-top: 1px solid var(--border);
      color: var(--text-secondary);
      font-size: 0.8rem;
      text-align: center;
    }

    footer.site-footer a { color: var(--text-secondary); }
  </style>
</head>
<body>
  <header class="site-header">
    <h1><a href="${SITE_URL}">${SITE_NAME}</a></h1>
    <p>AI-powered software engineering and consulting</p>
  </header>

  <main>
${articles}
  </main>

  <footer class="site-footer">
    <p>&copy; 2026 <a href="${SITE_URL}">CodaCon AI Inc.</a> &middot;
    Code: <a href="https://github.com/codaconai/blog-codacon-net">Apache-2.0</a> &middot;
    Content: <a href="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0</a></p>
  </footer>
</body>
</html>
HTMLEOF

echo "Built ${OUTPUT} with ${#post_files[@]} post(s)."
