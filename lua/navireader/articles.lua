local M = {}

-- Parse frontmatter from markdown file
local function parse_frontmatter(content)
  local article = {}
  local in_frontmatter = false
  local frontmatter_lines = {}
  local body_lines = {}
  local found_end = false

  for line in content:gmatch("[^\n]*") do
    if not found_end then
      if line:match("^---") then
        if not in_frontmatter then
          in_frontmatter = true
        else
          found_end = true
        end
      elseif in_frontmatter then
        table.insert(frontmatter_lines, line)
      end
    else
      table.insert(body_lines, line)
    end
  end

  -- Parse frontmatter fields
  for _, line in ipairs(frontmatter_lines) do
    local key, value = line:match("^([^:]+):%s*(.*)$")
    if key and value then
      key = key:gsub("^%s*", ""):gsub("%s*$", "")
      value = value:gsub("^%s*", ""):gsub("%s*$", "")

      if key == "read" or key == "starred" then
        article[key] = value == "true"
      elseif key == "date" then
        article["published"] = value
      else
        article[key] = value
      end
    end
  end

  article.content = table.concat(body_lines, "\n")
  return article
end

-- Get all articles from the cache directory
function M.get_articles(limit, options)
  options = options or {}
  local show_read = options.show_read  -- Default to false (don't show read items)

  local navireader = require("navireader")
  local config = navireader.get_config()
  local articles_dir = config.navireader_path .. "/articles"

  local articles = {}

  -- Get all .md files
  local handle = io.popen("ls " .. vim.fn.shellescape(articles_dir) .. "/*.md 2>/dev/null")
  local result = handle:read("*a")
  handle:close()

  local files = vim.split(result, "\n")

  for _, filepath in ipairs(files) do
    if filepath ~= "" and vim.fn.filereadable(filepath) == 1 then
      local content = vim.fn.readfile(filepath)
      local article = parse_frontmatter(table.concat(content, "\n"))
      article.filepath = filepath

      -- Filter out read articles if requested
      if show_read or not article.read then
        table.insert(articles, article)
      end
    end
  end

  -- Sort by date (newest first)
  table.sort(articles, function(a, b)
    -- Handle missing dates
    if not a.published and not b.published then
      return false
    elseif not a.published then
      return false
    elseif not b.published then
      return true
    end

    -- Compare dates (newer first)
    return a.published > b.published
  end)

  -- Apply limit after filtering and sorting
  if limit and #articles > limit then
    local limited = {}
    for i = 1, limit do
      limited[i] = articles[i]
    end
    return limited
  end

  return articles
end

-- Search articles
function M.search_articles(query)
  local articles = M.get_articles()
  local results = {}
  local query_lower = query:lower()

  for _, article in ipairs(articles) do
    local searchable = string.format("%s %s %s",
      article.title or "",
      article.content or "",
      article.feed or ""
    ):lower()

    if searchable:find(query_lower, 1, true) then
      table.insert(results, article)
    end
  end

  return results
end

-- Mark article as read
function M.mark_as_read(article_id)
  local articles = M.get_articles()

  for _, article in ipairs(articles) do
    if article.id == article_id and article.filepath then
      M.update_article_field(article.filepath, "read", "true")
      return true
    end
  end

  return false
end

-- Toggle star on article
function M.toggle_star(article_id)
  local articles = M.get_articles()

  for _, article in ipairs(articles) do
    if article.id == article_id and article.filepath then
      local new_value = article.starred and "false" or "true"
      M.update_article_field(article.filepath, "starred", new_value)
      return true
    end
  end

  return false
end

-- Update a field in the article's frontmatter
function M.update_article_field(filepath, field, value)
  local lines = vim.fn.readfile(filepath)
  local in_frontmatter = false
  local updated = false

  for i, line in ipairs(lines) do
    if line:match("^---") then
      if not in_frontmatter then
        in_frontmatter = true
      else
        in_frontmatter = false
      end
    elseif in_frontmatter and line:match("^" .. field .. ":") then
      lines[i] = field .. ": " .. value
      updated = true
      break
    end
  end

  if updated then
    vim.fn.writefile(lines, filepath)
  end
end

-- Get stats
function M.get_stats()
  local articles = M.get_articles()
  local unread_count = 0

  for _, article in ipairs(articles) do
    if not article.read then
      unread_count = unread_count + 1
    end
  end

  return {
    total = #articles,
    unread = unread_count,
  }
end

return M