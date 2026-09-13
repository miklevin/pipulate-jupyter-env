import os
import sys
import json
import yaml
import re
from datetime import datetime
from pathlib import Path
import llm
import argparse
import time
import common
import lsa

# --- CONFIGURATION ---
CONFIG_DIR = Path.home() / ".config" / "articleizer"

ARTICLE_FILENAME = "article.txt"
PROMPT_FILENAME = "editing_prompt.txt"
PROMPT_PLACEHOLDER = "[INSERT FULL ARTICLE]"
INSTRUCTIONS_CACHE_FILE = "instructions.json"

# Model Selection - Use a stable model to avoid low quotas
DEFAULT_MODEL = 'gemini-flash-latest'
# DEFAULT_MODEL = 'gemini-flash-lite-latest'

SPINE_PLACEHOLDER = "[INSERT BOOK SPINE]"
# THE BLOG FOLDER REACHES THE MODEL (banked 2026-09-04). editing_prompt.txt is
# what CAUSES every post's frontmatter to say /futureproof/, so leaving it
# hardwired meant blogs.nix could declare a folder that nothing ever wrote.
# A PATTERN, NOT A PREFIX, and the name follows the value: what gets
# substituted is a whole permalink shape ("/futureproof/[slug]/"), because a
# bare segment would force the template to spell "/[PREFIX]/[slug]/" and an
# empty prefix would then yield a doubled slash -- the exact case
# default_permalink exists to avoid. That same function builds this string,
# so the instruction the model receives and the fallback lsa.py uses can never
# disagree: one function, both answers.
# BASE URL RIDES ALONG because the tweet example hardwired the HOSTNAME too,
# and templating only the folder would hand grimoire the public site's host.
PERMALINK_PATTERN_PLACEHOLDER = "[INSERT PERMALINK PATTERN]"
BASE_URL_PLACEHOLDER = "[INSERT BASE URL]"


def scan_corpus(output_dir):
    """One-pass frontmatter scan of the published corpus.

    Returns (entries, errors): entries is a list of dicts with filename,
    date, slug (date-stripped), permalink, and title; errors counts posts
    whose frontmatter could not be read (census-incompleteness signal).
    """
    entries, errors = [], 0
    target = Path(output_dir)
    if not target.exists():
        return entries, errors
    for post in sorted(target.glob("*.md")):
        stem = post.stem
        slug = re.sub(r'^\d{4}-\d{2}-\d{2}-', '', stem)
        date = stem[:10]
        title, permalink = "", ""
        try:
            content = post.read_text(encoding='utf-8')
            if content.startswith('---'):
                parts = content.split('---', 2)
                if len(parts) >= 3:
                    fm = yaml.safe_load(parts[1]) or {}
                    title = str(fm.get('title') or "")
                    permalink = str(fm.get('permalink') or "")
        except Exception:
            errors += 1
        entries.append({'filename': post.name, 'date': date, 'slug': slug,
                        'permalink': permalink, 'title': title})
    return entries, errors


def normalize_permalink(permalink):
    """Case-insensitive, slash-agnostic identity for collision checks."""
    return (permalink or "").strip().strip('/').lower()


def build_taken_identities(entries):
    """Map every taken slug and permalink identity to its owning filename."""
    taken = {}
    for e in entries:
        taken.setdefault(e['slug'].lower(), e['filename'])
        p = normalize_permalink(e['permalink'])
        if p:
            taken.setdefault(p, e['filename'])
    return taken


SPINE_FULL_DETAIL_COUNT = 150  # newest N entries carry date+slug+title


def build_book_spine(entries, full_detail_count=SPINE_FULL_DETAIL_COUNT):
    """Two-tier spine for the editing model's 40K view.

    Deep archive rides as bare slugs (the uniqueness census — the slug IS
    the identity, and the deterministic collision guard enforces it anyway);
    the newest entries ride full 'date slug | title' (the trajectory arc).
    Deterministic and non-generative; ~58% smaller than the all-titles spine.
    """
    if full_detail_count <= 0 or len(entries) <= full_detail_count:
        older, recent = [], entries
    else:
        older, recent = entries[:-full_detail_count], entries[-full_detail_count:]
    lines = [e['slug'] for e in older]
    if older and recent:
        lines.append("--- RECENT ENTRIES (full detail) ---")
    lines += [f"{e['date']} {e['slug']} | {e['title']}" for e in recent]
    return "\n".join(lines)

def create_jekyll_post(article_content, instructions, output_dir, preview_port, base_url=""):
    """
    Assembles and writes a Jekyll post file from the article content and
    structured AI-generated instructions.
    
    Auto-increments 'sort_order' based on existing posts for the current date.
    Wraps content in Liquid {% raw %} tags to prevent template errors.
    """
    print("Formatting final Jekyll post...")

    # 1. Determine Date and Auto-Increment Sort Order
    current_date = datetime.now().strftime('%Y-%m-%d')
    next_sort_order = 1
    
    try:
        target_path = Path(output_dir)
        if target_path.exists():
            # Find all markdown files for today
            todays_posts = list(target_path.glob(f"{current_date}-*.md"))
            
            max_order = 0
            for post_file in todays_posts:
                try:
                    # Read content to parse front matter
                    content = post_file.read_text(encoding='utf-8')
                    if content.startswith('---'):
                        # Split to isolate YAML block (between first two ---)
                        parts = content.split('---', 2)
                        if len(parts) >= 3:
                            front_matter = yaml.safe_load(parts[1])
                            if front_matter and 'sort_order' in front_matter:
                                try:
                                    order = int(front_matter['sort_order'])
                                    if order > max_order:
                                        max_order = order
                                except (ValueError, TypeError):
                                    continue
                except Exception as e:
                    print(f"Warning checking sort_order in {post_file.name}: {e}")
            
            if max_order > 0:
                next_sort_order = max_order + 1
                print(f"📅 Found {len(todays_posts)} posts for today. Auto-incrementing sort_order to {next_sort_order}.")
            else:
                print(f"📅 First post of the day. sort_order set to 1.")
                
    except Exception as e:
        print(f"⚠️ Could not calculate auto-increment sort_order: {e}. Defaulting to 1.")

    # 2. Prepare Data
    editing_instr = instructions.get("editing_instructions", {})
    analysis_content = instructions.get("book_analysis_content", {})
    yaml_updates = editing_instr.get("yaml_updates", {})

    # --- NEW: Construct the absolute Canonical URL ---
    permalink = yaml_updates.get("permalink", "")
    # Ensure proper slash formatting
    if not permalink.startswith("/"):
        permalink = f"/{permalink}"
    base_url = (base_url or "").rstrip("/")
    canonical_url = f"{base_url}{permalink}" if base_url else ""
    # -----------------------------------------------

    new_yaml_data = {
        'title': yaml_updates.get("title"),
        'permalink': permalink,
        'canonical_url': canonical_url,  # <--- INJECTED HERE
        'description': analysis_content.get("authors_imprint"),
        'meta_description': yaml_updates.get("description"),
        'excerpt': yaml_updates.get("description"),
        'meta_keywords': yaml_updates.get("keywords"),
        'layout': 'post',
        'sort_order': next_sort_order
    }


    # 3. Assemble Content
    final_yaml_block = f"---\n{yaml.dump(new_yaml_data, Dumper=yaml.SafeDumper, sort_keys=False, default_flow_style=False)}---"

    article_body = article_content.strip()
    
    # --- NEW: Fix Dialogue Header Collisions ---
    # Converts "**Speaker**: ### Header" to "**Speaker**:\n\n### Header"
    article_body = re.sub(r'(\*\*[^*]+\*\*:\s*)(#{1,6}\s)', r'\1\n\n\2', article_body)
    # -------------------------------------------

    # --- NEW: Compress Code Block Spacing ---
    # Replaces double newlines before a closing code block with a single newline
    article_body = re.sub(r'\n\n```\n', '\n```\n', article_body)
    # -------------------------------------------

    article_body = f"## Technical Journal Entry Begins\n\n{article_body}"

    subheadings = editing_instr.get("insert_subheadings", [])
    for item in reversed(subheadings):
        snippet = item.get("after_text_snippet", "")
        subheading = item.get("subheading", "## Missing Subheading")
        if not snippet:
            print(f"Warning: Skipping subheading '{subheading}' due to missing snippet.")
            continue

        words = re.findall(r'\w+', snippet.lower())
        pattern_text = r'.*?'.join(re.escape(word) for word in words)

        match = re.search(pattern_text, article_body, re.IGNORECASE | re.DOTALL)
        if match:
            # SAFETY FIX: Force insertion to the nearest paragraph break (double newline).
            # This prevents headlines from splitting sentences or paragraphs mid-stream.
            match_end = match.end()
            
            # Find the next double newline starting from the end of the match
            insertion_point = article_body.find('\n\n', match_end)
            
            # If no paragraph break is found (end of document), append to the very end.
            if insertion_point == -1:
                insertion_point = len(article_body)
            
            # HEADING COLLISION GUARD (optics-convicted 2026-07-12): when the
            # article body already carries its own markdown headers (dialogue
            # partners now write them), inserting ours immediately before an
            # existing one creates stacked/empty H2s — the orphan-header
            # pattern the Semantic Outline lens caught on the Dune article.
            following = article_body[insertion_point:].lstrip('\n')
            if following.startswith('#'):
                print(f"Skipping subheading '{subheading}': heading already present at insertion point.")
                continue

            # Insert the subheading surrounded by newlines.
            # If insertion_point finds an existing '\n\n', this logic adds another '\n\n'
            # effectively creating: [End of Para]\n\n[Subheading]\n\n[Start of Next Para]
            article_body = (
                article_body[:insertion_point] +
                f"\n\n{subheading}" +
                article_body[insertion_point:]
            )
        else:
            print(f"Warning: Snippet not found for subheading '{subheading}': '{snippet}'")

    prepend_text = editing_instr.get("prepend_to_article_body", "")
    if prepend_text:
        intro_section = f"## Setting the Stage: Context for the Curious Book Reader\n\n{prepend_text}\n\n---"
        article_body = f"{intro_section}\n\n{article_body}"

    # --- WRAPPING LOGIC START ---
    # Wrap the entire body in {% raw %} ... {% endraw %} to prevent Liquid processing errors
    # only if it's not already wrapped.
    if not article_body.strip().startswith("{% raw %}"):
        article_body = f"{{% raw %}}\n{article_body}\n{{% endraw %}}"
    # --- WRAPPING LOGIC END ---

    analysis_markdown = "\n## Book Analysis\n"
    if 'ai_editorial_take' in analysis_content:
        analysis_markdown += f"\n### Ai Editorial Take\n{analysis_content['ai_editorial_take']}\n"
    if 'promotional_tweet' in analysis_content:
        analysis_markdown += f"\n### 🐦 X.com Promo Tweet\n```text\n{analysis_content['promotional_tweet']}\n```\n"
    for key, value in analysis_content.items():
        if key in ['authors_imprint', 'ai_editorial_take', 'promotional_tweet']:
            continue
        title = key.replace('_', ' ').title()
        analysis_markdown += f"\n### {title}\n"
        if isinstance(value, list):
            for item in value:
                if isinstance(item, dict):
                    analysis_markdown += f"* **Title Option:** {item.get('title', 'N/A')}\n"
                    analysis_markdown += f"  * **Filename:** `{item.get('filename', 'N/A')}`\n"
                    analysis_markdown += f"  * **Rationale:** {item.get('rationale', 'N/A')}\n"
                else:
                    analysis_markdown += f"- {item}\n"
        elif isinstance(value, dict):
            for sub_key, sub_value in value.items():
                analysis_markdown += f"- **{sub_key.replace('_', ' ').title()}:**\n"
                if isinstance(sub_value, list):
                    for point in sub_value:
                        analysis_markdown += f"  - {point}\n"
                else:
                    analysis_markdown += f"  - {sub_value}\n"
        else:
            analysis_markdown += f"{value}\n"

    final_content = f"{final_yaml_block}\n\n{article_body}\n\n---\n{analysis_markdown}"

    # 4. Generate Filename
    slug = "untitled-article"
    title_brainstorm = analysis_content.get("title_brainstorm", [])
    if title_brainstorm and title_brainstorm[0].get("filename"):
        slug = os.path.splitext(title_brainstorm[0]["filename"])[0]

    output_filename = f"{current_date}-{slug}.md"

    # --- COLLISION GUARD (deterministic, corpus-wide) ---
    entries, scan_errors = scan_corpus(output_dir)
    taken = build_taken_identities(entries)
    if scan_errors:
        print(f"⚠️ Collision census incomplete: {scan_errors} post(s) unreadable.")
    collisions = []
    slug_owner = taken.get(slug.lower())
    if slug_owner and slug_owner != output_filename:
        collisions.append(f"slug '{slug}' already owned by {slug_owner}")
    perma_owner = taken.get(normalize_permalink(permalink))
    if perma_owner and perma_owner != output_filename:
        collisions.append(f"permalink '{permalink}' already owned by {perma_owner}")
    if collisions:
        print("🛑 COLLISION GUARD: refusing to write new article.")
        for c in collisions:
            print(f"   - {c}")
        print("   Pick a new slug/permalink (edit instructions.json, rerun with --local).")
        return None

    output_path = os.path.join(output_dir, output_filename)
    os.makedirs(output_dir, exist_ok=True)

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(final_content)

    print(f"✨ Success! Article saved to: {output_path}")
    print("Collect new 404s: python prompt_foo.py assets/prompts/find404s.md --chop CHOP_404_AFFAIR -l [:] --no-tree")

    # --- NEW: Construct Preview URL and Copy to Clipboard ---
    local_url = f"http://localhost:{preview_port}{permalink}"
    try:
        import subprocess
        subprocess.run(
            ['xclip', '-selection', 'clipboard'], 
            input=local_url.encode('utf-8'), 
            check=True
        )
        print(f"🔗 Paste-ready preview URL copied to clipboard:\n   {local_url}")
    except Exception as e:
        print(f"⚠️ Could not copy URL to clipboard: {e}")

    return output_path

def main():
    parser = argparse.ArgumentParser(description="Process an article with the Gemini API and format it for Jekyll.")
    parser.add_argument(
        '-l', '--local',
        action='store_true',
        help=f"Use local '{INSTRUCTIONS_CACHE_FILE}' cache instead of calling the API."
    )
    parser.add_argument(
        '--copy',
        action='store_true',
        help="Copy the generated prompt to the clipboard and exit without calling the API."
    )
    common.add_standard_arguments(parser)
    args = parser.parse_args()

    # Use common to securely lock target
    output_dir = common.get_target_path(args)

    # Fetch the target configuration to get the preview port
    targets = common.load_targets()
    target_config = targets.get(str(args.target), targets.get("1", {}))
    preview_port = target_config.get("preview_port", 4000) # Default to 4000

    if not os.path.exists(ARTICLE_FILENAME):
        print(f"Error: Article file '{ARTICLE_FILENAME}' not found.")
        return
    with open(ARTICLE_FILENAME, 'r', encoding='utf-8') as f:
        article_text = f.read()

    instructions = None

    if args.local:
        print(f"Attempting to use local cache file: {INSTRUCTIONS_CACHE_FILE}")
        if not os.path.exists(INSTRUCTIONS_CACHE_FILE):
            print(f"Error: Cache file not found. Run without --local to create it.")
            return
        try:
            with open(INSTRUCTIONS_CACHE_FILE, 'r', encoding='utf-8') as f:
                instructions = json.load(f)
            print("Successfully loaded instructions from local cache.")
        except json.JSONDecodeError:
            print("Error: Could not parse the local instructions cache file. It may be corrupt.")
            return
    else:
        api_key = common.get_api_key(args.key)
        if not api_key:
            print("API Key not provided. Exiting.")
            return

        if not os.path.exists(PROMPT_FILENAME):
            print(f"Error: Prompt file '{PROMPT_FILENAME}' not found.")
            return
        with open(PROMPT_FILENAME, 'r', encoding='utf-8') as f:
            prompt_template = f.read()

        # SUBSTITUTE INTO THE TEMPLATE, BEFORE THE ARTICLE LANDS. The order is
        # load-bearing for the guard below: an article ABOUT this system quotes
        # placeholder names in its prose (the one introducing this code does),
        # so a guard run on the ASSEMBLED prompt would refuse to publish the
        # very article documenting the mechanism -- THE INSTRUMENT BECOMES
        # BAIT. Scanning the template alone cannot see the article and so
        # cannot be baited by it.
        prompt_prefix = lsa.permalink_prefix(target_config)
        # `is None`, never `or`: target 4 declares base_url = "" ON PURPOSE
        # (a private wiki with no public URL), and an or-chain would hand it
        # the public site's hostname. Mirrors this file's own canonical_url
        # logic further down, and permalink_prefix's None-vs-falsy rule.
        prompt_base_url = target_config.get("base_url")
        if prompt_base_url is None:
            prompt_base_url = target_config.get("url", "https://mikelev.in")
        prompt_template = prompt_template.replace(
            PERMALINK_PATTERN_PLACEHOLDER,
            lsa.default_permalink("[slug]", prompt_prefix) + "/")
        prompt_template = prompt_template.replace(
            BASE_URL_PLACEHOLDER, prompt_base_url.rstrip("/"))
        # THE UNSUBSTITUTED-PLACEHOLDER AIRLOCK: if editing_prompt.txt carries
        # a placeholder this file does not know -- a typo, or a template
        # patched ahead of its reader -- the literal "[INSERT ...]" reaches the
        # model and lands verbatim in a permalink. Refuse instead. FULL ARTICLE
        # and BOOK SPINE are exempt because they are substituted after this
        # point, which is the only reason this guard can run here at all.
        leftover = sorted(set(re.findall(r"\[INSERT [A-Z ]+\]", prompt_template))
                          - {PROMPT_PLACEHOLDER, SPINE_PLACEHOLDER})
        if leftover:
            print(f"❌ Unsubstituted placeholder(s) in {PROMPT_FILENAME}: {leftover}")
            print("   Refusing to call the API; the model would copy the literal text into your frontmatter.")
            return
        full_prompt = prompt_template.replace(PROMPT_PLACEHOLDER, article_text)

        # --- BOOK SPINE INJECTION (40K-foot view for the editing model) ---
        if SPINE_PLACEHOLDER in full_prompt:
            spine_entries, spine_errors = scan_corpus(output_dir)
            if spine_errors:
                print(f"⚠️ Spine census incomplete: {spine_errors} post(s) unreadable.")
            spine = build_book_spine(spine_entries)
            full_prompt = full_prompt.replace(SPINE_PLACEHOLDER, spine)
            print(f"📚 Book spine injected: {len(spine_entries)} articles, {len(spine):,} chars.")

        if args.copy:
            try:
                # We borrow the existing robust clipboard function from prompt_foo
                import subprocess
                subprocess.run(['pbcopy'] if sys.platform == 'darwin' else ['xclip', '-selection', 'clipboard'], input=full_prompt.encode('utf-8'), check=True)
                print("📋 Prompt copied to clipboard! You can now paste it into any web UI.")
            except Exception as e:
                print(f"❌ Failed to copy to clipboard: {e}")
            return

        print(f"Calling the Universal Adapter (using {DEFAULT_MODEL})...")
        max_retries = 5
        retry_delay = 2
        for attempt in range(max_retries):
            try:
                # Use a free-tier compatible model.
                model = llm.get_model(DEFAULT_MODEL)
                model.key = api_key  # Assign the key directly to the adapter
                response = model.prompt(full_prompt)
                gemini_output = response.text()
                print("Successfully received response from API.")
                
                json_match = re.search(r'```json\s*([\s\S]*?)\s*```', gemini_output)
                json_str = json_match.group(1) if json_match else gemini_output
                instructions = json.loads(json_str)
                print("Successfully parsed JSON instructions.")
                
                with open(INSTRUCTIONS_CACHE_FILE, 'w', encoding='utf-8') as f:
                    json.dump(instructions, f, indent=4)
                print(f"✅ Instructions saved to '{INSTRUCTIONS_CACHE_FILE}' for future use.")
                break  # Exit the loop on success
            
            except Exception as e:
                # Check for retriable server-side or rate-limit errors
                error_str = str(e)
                if ("429" in error_str and "Quota" in error_str) or \
                   ("504" in error_str and "timed out" in error_str) or \
                   ("503" in error_str) or \
                   ("500" in error_str) or \
                   ("high demand" in error_str.lower()):
                    
                    print(f"Retriable API Error: {e}")
                    # QUOTA WINDOW DISCIPLINE (live-fire convicted 2026-07-19):
                    # the free tier is a per-MINUTE rolling window; retrying at
                    # 2/4/8/16s hammers the same window the server asked us to
                    # let drain. Honor the server's own "retry in Ns" hint.
                    hint = re.search(r'retry in (\d+(?:\.\d+)?)s', error_str)
                    wait = max(retry_delay, float(hint.group(1)) + 1) if hint else retry_delay
                    print(f"Retrying in {wait:.0f} seconds... (Attempt {attempt + 1}/{max_retries})")

                    time.sleep(wait)
                    retry_delay *= 2  # Exponential backoff
                else:
                    print(f"\nAn unrecoverable error occurred while calling the API: {e}")
                    if 'gemini_output' in locals():
                        print("--- API Raw Output ---\n" + gemini_output)
                    return
        else: # This block runs if the loop completes without a break
            print("Error: Max retries exceeded. Failed to get a successful response from the API.")
            return

    if instructions:
        base_url = target_config.get("base_url")
        if base_url is None:
            base_url = target_config.get("url", "https://mikelev.in")
        saved_path = create_jekyll_post(article_text, instructions, output_dir, preview_port, base_url)
        if saved_path:
            common.record_last_published(args.target, saved_path, target_config.get("name"))


if __name__ == '__main__':
    main()
