-- This filter transforms Asciidoctor's admonition blocks into GitHub Flavored Markdown alerts.

-- This filter works by finding a Div with class "admonitionblock", then
-- walking its contents to find the table cell (<td>) with class "content".
-- It then extracts the content of that cell, prepends a GFM alert header
-- like "[!NOTE]", and wraps the whole thing in a blockquote.

-- Define a walker to find the content cell.
-- We use a variable in the parent scope to store the result.
local content_cell_blocks = nil
local walker = {
  Cell = function(cell)
    -- The admonition content is in a cell with class "content".
    if cell.attr.classes:includes('content') then
      content_cell_blocks = cell.content
    end
    return cell
  end
}

function Div(div)
  -- Asciidoctor creates a div with class "admonitionblock" and a second class
  -- for the type (e.g., "note", "important").
  if not div.classes:includes("admonitionblock") then
    return div -- Not an admonition block, do nothing.
  end

  -- Determine the admonition type from the div's classes.
  local admonition_type = ""
  local type_map = { note = "NOTE", important = "IMPORTANT", tip = "TIP", warning = "WARNING", caution = "CAUTION" }
  for class, type in pairs(type_map) do
    if div.classes:includes(class) then
      admonition_type = type
      break
    end
  end

  if admonition_type == "" then
    return div -- Unknown admonition type, do nothing.
  end

  -- Reset and run the walker to find the content cell's blocks.
  content_cell_blocks = nil
  pandoc.walk_block(div, walker)

  if content_cell_blocks then
    -- The cell content is wrapped in further divs (e.g., class="paragraph").
    -- We need to extract the actual content blocks from them.
    local extracted_blocks = {}
    for _, block in ipairs(content_cell_blocks) do
      if block.t == 'Div' and block.content then
        for _, inner_block in ipairs(block.content) do
          table.insert(extracted_blocks, inner_block)
        end
      else
        table.insert(extracted_blocks, block)
      end
    end

    -- Create the GFM alert header, e.g., '[!IMPORTANT]'
    local alert_header = pandoc.Para{
      pandoc.RawInline('markdown', '[!' .. admonition_type .. ']')
    }

    -- Prepend the header and wrap everything in a BlockQuote.
    table.insert(extracted_blocks, 1, alert_header)
    return pandoc.BlockQuote(extracted_blocks)
  end

  -- If we didn't find a content cell, return the div unchanged.
  return div
end
