vim9script
# Converts Atlassian Document Format (ADF) to Markdown-like text lines.
# Jira Cloud REST API v3 returns descriptions and comments as ADF.
# Unknown node types fall back to their text content.

export def ToLines(doc: any): list<string>
  if type(doc) != v:t_dict
    return []
  endif
  return Blocks(Content(doc), false)
enddef

def Content(node: any): list<any>
  const c = type(node) == v:t_dict ? get(node, 'content', []) : []
  return type(c) == v:t_list ? c : []
enddef

def Attrs(node: dict<any>): dict<any>
  const a = get(node, 'attrs', {})
  return type(a) == v:t_dict ? a : {}
enddef

# Renders block nodes; blocks are separated by a blank line unless tight.
def Blocks(nodes: list<any>, tight: bool): list<string>
  var lines: list<string> = []
  for node in nodes
    const block = Block(node)
    if empty(block)
      continue
    endif
    if !tight && !empty(lines)
      add(lines, '')
    endif
    extend(lines, block)
  endfor
  return lines
enddef

def Block(node: dict<any>): list<string>
  const t = get(node, 'type', '')
  const attrs = Attrs(node)
  const content = Content(node)

  if t == 'paragraph'
    const text = Inline(content)
    return empty(text) ? [] : split(text, "\n", true)
  elseif t == 'heading'
    return [repeat('#', min([get(attrs, 'level', 1) + 2, 6])) .. ' ' .. Inline(content)]
  elseif t == 'bulletList'
    return List(content, false, 1)
  elseif t == 'orderedList'
    return List(content, true, get(attrs, 'order', 1))
  elseif t == 'codeBlock'
    return ['```' .. get(attrs, 'language', '')]
      + split(Inline(content), "\n", true) + ['```']
  elseif t == 'blockquote'
    return Blocks(content, false)->map((_, l) => empty(l) ? '>' : '> ' .. l)
  elseif t == 'rule'
    return ['---']
  elseif t == 'table'
    return content->mapnew((_, row) => '| ' .. Content(row)
      ->mapnew((_, cell) => join(Blocks(Content(cell), true), ' '))
      ->join(' | ') .. ' |')
  elseif t == 'mediaSingle' || t == 'mediaGroup' || t == 'media'
    return ['[attachment]']
  elseif !empty(content) && t != 'text'
    return Blocks(content, false)
  endif
  const text = Inline([node])
  return empty(text) ? [] : split(text, "\n", true)
enddef

def List(items: list<any>, ordered: bool, start: number): list<string>
  var lines: list<string> = []
  var n = start
  for item in items
    const marker = ordered ? n .. '. ' : '- '
    const indent = repeat(' ', len(marker))
    var body = Blocks(Content(item), true)
    if empty(body)
      body = ['']
    endif
    add(lines, marker .. body[0])
    for l in body[1 :]
      add(lines, empty(l) ? '' : indent .. l)
    endfor
    n += 1
  endfor
  return lines
enddef

def Inline(nodes: list<any>): string
  var s = ''
  for node in nodes
    const t = get(node, 'type', '')
    const attrs = Attrs(node)
    if t == 'text'
      s ..= Marks(get(node, 'text', ''), get(node, 'marks', []))
    elseif t == 'hardBreak'
      s ..= "\n"
    elseif t == 'mention'
      s ..= get(attrs, 'text', '@user')
    elseif t == 'emoji'
      s ..= get(attrs, 'text', get(attrs, 'shortName', ''))
    elseif t == 'inlineCard' || t == 'blockCard'
      s ..= get(attrs, 'url', '')
    elseif t == 'date'
      s ..= strftime('%Y-%m-%d', str2nr(get(attrs, 'timestamp', '0')) / 1000)
    elseif t == 'status'
      s ..= '[' .. get(attrs, 'text', '') .. ']'
    else
      s ..= Inline(Content(node))
    endif
  endfor
  return s
enddef

# ----------------------------------------------------------------------------
# Text -> ADF (for editing descriptions and writing comments)
#
# Understands the subset that ToLines() produces: paragraphs (line breaks
# become hard breaks), "#" headings, "-"/"*" and "1." lists (nested by
# indentation), ``` code blocks, "> " quotes and "---" rules. Everything
# else is kept as plain text. Returns v:null for empty text.

const LIST_ITEM = '^\%([-*]\|\d\+\.\) '

def IsBlockStart(line: string): bool
  return line =~ '^```' || line =~ '^#\{1,6} ' || line =~ '^---\+\s*$'
    || line =~ '^>' || line =~ LIST_ITEM
enddef

def TextNodes(text: string): list<any>
  return empty(text) ? [] : [{type: 'text', text: text}]
enddef

export def FromLines(lines: list<string>): any
  const blocks = ParseBlocks(lines)
  return empty(blocks) ? null : {type: 'doc', version: 1, content: blocks}
enddef

def ParseBlocks(lines: list<string>): list<any>
  var blocks: list<any> = []
  var i = 0
  const n = len(lines)
  while i < n
    const line = lines[i]
    if line =~ '^\s*$'
      i += 1
    elseif line =~ '^```'
      var code: list<string> = []
      i += 1
      while i < n && lines[i] !~ '^```'
        add(code, lines[i])
        i += 1
      endwhile
      i += 1
      var node: dict<any> = {type: 'codeBlock', content: TextNodes(join(code, "\n"))}
      const lang = matchstr(line, '^```\s*\zs\S\+')
      if !empty(lang)
        node.attrs = {language: lang}
      endif
      add(blocks, node)
    elseif line =~ '^#\{1,6} '
      # ToLines() writes level N as N+2 "#"s.
      const level = max([1, len(matchstr(line, '^#\+')) - 2])
      add(blocks, {type: 'heading', attrs: {level: level},
        content: TextNodes(substitute(line, '^#\+ ', '', ''))})
      i += 1
    elseif line =~ '^---\+\s*$'
      add(blocks, {type: 'rule'})
      i += 1
    elseif line =~ '^>'
      var quoted: list<string> = []
      while i < n && lines[i] =~ '^>'
        add(quoted, substitute(lines[i], '^> \?', '', ''))
        i += 1
      endwhile
      add(blocks, {type: 'blockquote', content: ParseBlocks(quoted)})
    elseif line =~ LIST_ITEM
      const ordered = line =~ '^\d'
      var items: list<any> = []
      while i < n && lines[i] =~ LIST_ITEM && (lines[i] =~ '^\d') == ordered
        const marker = matchstr(lines[i], LIST_ITEM)
        var body = [strpart(lines[i], len(marker))]
        i += 1
        while i < n && lines[i] =~ '^\s\+\S'
          add(body, substitute(lines[i], '^ \{1,' .. len(marker) .. '}', '', ''))
          i += 1
        endwhile
        add(items, {type: 'listItem', content: ParseBlocks(body)})
      endwhile
      var listnode: dict<any> = {type: ordered ? 'orderedList' : 'bulletList',
        content: items}
      if ordered
        listnode.attrs = {order: str2nr(line)}
      endif
      add(blocks, listnode)
    else
      var inline: list<any> = []
      while i < n && lines[i] !~ '^\s*$' && (empty(inline) || !IsBlockStart(lines[i]))
        if !empty(inline)
          add(inline, {type: 'hardBreak'})
        endif
        extend(inline, TextNodes(lines[i]))
        i += 1
      endwhile
      add(blocks, {type: 'paragraph', content: inline})
    endif
  endwhile
  return blocks
enddef

def Marks(text: string, marks: any): string
  var s = text
  if type(marks) != v:t_list
    return s
  endif
  for mark in marks
    const t = get(mark, 'type', '')
    if t == 'code'
      s = '`' .. s .. '`'
    elseif t == 'link'
      const href = get(Attrs(mark), 'href', '')
      if !empty(href) && href != text
        s ..= ' <' .. href .. '>'
      endif
    endif
  endfor
  return s
enddef
