// What the preset browser searches: the factory presets, the list the header's arrows step
// through (a bank the user loaded), the files the plugin keeps (BankLibrary: those in the user's
// preset folders, and files opened before), and files opened in the browser. Searching and
// filtering live here, apart from the browser's elements.
//
// A search is words and field filters: every word must appear in the name, category, tags,
// author, description or source, and every filter in its field ("tag:wide", "cat:pad",
// "author:someone", "name:keys"; quotes keep spaces: tag:"per-voice pan"). On top of that,
// the browser's facets pick categories (any of them), tags (all of them) and authors (any).

// List: the current list, when it's none of the others; Cached: in the plugin's bank library
type kind = Factory | List | Cached | File

type status = Loading | Ready | Failed(string)

type source = {
  id: string,
  mutable name: string,
  kind: kind,
  mutable status: status,
  mutable presets: array<Preset.t>,
}

type entry = {source: source, index: int, preset: Preset.t}

let makeSource = (~id, ~name, ~kind, ~presets=[]) => {
  id,
  name,
  kind,
  status: presets == [] ? Loading : Ready,
  presets,
}

// Unused slots of a bank ("Init 17"). They are left out, except for the current list's when
// ~emptySlots is set (the browser shows them when it lists just that one).
let isPlaceholder = (p: Preset.t) =>
  RegExp.test(/^init( \d+)?$/i, String.trim(p.name)) && p.description == "" && p.tags == []

let entries = (sources: array<source>, ~emptySlots=false) =>
  sources->Array.flatMap(source =>
    source.presets
    ->Array.mapWithIndex((preset, index) => {source, index, preset})
    ->Array.filter(e => emptySlots || !isPlaceholder(e.preset))
  )
//==============================================================================
// queries

let norm = s => s->String.trim->String.toLowerCase

type query = {
  words: array<string>,
  names: array<string>,
  tags: array<string>,
  categories: array<string>,
  authors: array<string>,
}

let emptyQuery = {words: [], names: [], tags: [], categories: [], authors: []}

// Splits on spaces, except inside double quotes (which are dropped).
let tokens = text => {
  let out = []
  let cur = ref("")
  let quoted = ref(false)
  let flush = () => {
    if cur.contents != "" {
      out->Array.push(cur.contents)
    }
    cur := ""
  }
  text
  ->String.split("")
  ->Array.forEach(ch =>
    switch ch {
    | "\"" => quoted := !quoted.contents
    | " " | "\t" if !quoted.contents => flush()
    | ch => cur := cur.contents ++ ch
    }
  )
  flush()
  out
}

let parse = text =>
  tokens(text)->Array.reduce(emptyQuery, (q, token) => {
    let (field, value) = switch token->String.indexOf(":") {
    | i if i > 0 => (norm(token->String.slice(~start=0, ~end=i)), norm(token->String.slice(~start=i + 1)))
    | _ => ("", norm(token))
    }
    switch (field, value) {
    | (_, "") => q
    | ("tag" | "tags" | "t", v) => {...q, tags: [...q.tags, v]}
    | ("cat" | "category" | "c", v) => {...q, categories: [...q.categories, v]}
    | ("author" | "by" | "a", v) => {...q, authors: [...q.authors, v]}
    | ("name" | "n", v) => {...q, names: [...q.names, v]}
    // an unknown field is just a word ("12:00")
    | _ => {...q, words: [...q.words, norm(token)]}
    }
  })

let isEmptyQuery = q =>
  q.words == [] && q.names == [] && q.tags == [] && q.categories == [] && q.authors == []

//==============================================================================
// facets

type facet = Category | Tag | Author

type filters = {
  // a source id, or None for every source
  source: option<string>,
  categories: array<string>,
  tags: array<string>,
  authors: array<string>,
}

let noFilters = {source: None, categories: [], tags: [], authors: []}

let toggle = (list, x) => list->Array.includes(x) ? list->Array.filter(y => y != x) : [...list, x]

let toggleFacet = (f, facet, value) =>
  switch facet {
  | Category => {...f, categories: toggle(f.categories, value)}
  | Tag => {...f, tags: toggle(f.tags, value)}
  | Author => {...f, authors: toggle(f.authors, value)}
  }

let hasFacets = f => f.categories != [] || f.tags != [] || f.authors != []

//==============================================================================
// matching

let category = (e: entry) => norm(e.preset.category)
let author = (e: entry) => norm(e.preset.author)
let tagsOf = (e: entry) => e.preset.tags->Array.map(norm)->Array.filter(t => t != "")

let haystack = (e: entry) =>
  [
    e.preset.name,
    e.preset.category,
    e.preset.author,
    e.preset.description,
    e.source.name,
    ...e.preset.tags,
  ]
  ->Array.map(norm)
  ->Array.join("\n")

let contains = (s, part) => s->String.includes(part)

let matchesQuery = (e: entry, q: query) => {
  let name = norm(e.preset.name)
  let tags = tagsOf(e)
  let all = haystack(e)
  q.names->Array.every(contains(name, _)) &&
  q.categories->Array.every(contains(category(e), _)) &&
  q.authors->Array.every(contains(author(e), _)) &&
  q.tags->Array.every(v => tags->Array.some(contains(_, v))) &&
  q.words->Array.every(contains(all, _))
}

// The filters, leaving out one facet (to count what picking from that facet would give).
let matchesFilters = (e: entry, f: filters, ~except=?) =>
  f.source->Option.mapOr(true, id => e.source.id == id) &&
  (except == Some(Category) || f.categories == [] || f.categories->Array.includes(category(e))) &&
  (except == Some(Author) || f.authors == [] || f.authors->Array.includes(author(e))) &&
  (except == Some(Tag) || f.tags->Array.every(t => tagsOf(e)->Array.includes(t)))

let matches = (e, q, f) => matchesFilters(e, f) && matchesQuery(e, q)

// How well an entry fits the words: names that start with a word first, then names that
// contain one, then exact tags and categories.
let score = (e: entry, q: query) => {
  let name = norm(e.preset.name)
  let tags = tagsOf(e)
  let spaced = " " ++ name->String.replaceRegExp(/[^a-z0-9]+/g, " ")
  let wordScore = w =>
    if name->String.startsWith(w) {
      6
    } else if spaced->contains(" " ++ w) {
      4
    } else if name->contains(w) {
      3
    } else if tags->Array.includes(w) || category(e) == w {
      2
    } else {
      0
    }
  q.words->Array.reduce(0, (s, w) => s + wordScore(w)) +
  q.names->Array.reduce(0, (s, w) => s + wordScore(w))
}

// The matching entries, best first when there are words, otherwise in bank order.
let search = (all: array<entry>, q, f) => {
  let found = all->Array.filter(matches(_, q, f))
  if q.words == [] && q.names == [] {
    found
  } else {
    found
    ->Array.mapWithIndex((e, i) => (e, score(e, q), i))
    ->Array.toSorted(((_, a, i), (_, b, j)) => a != b ? Int.toFloat(b - a) : Int.toFloat(i - j))
    ->Array.map(((e, _, _)) => e)
  }
}

// The values of a facet among the entries the rest of the search leaves, with how many
// entries have each, most common first (then alphabetical). Picked values are always listed.
let facetCounts = (all: array<entry>, q, f, facet) => {
  let counts = Map.make()
  let labels = Map.make()
  let add = (key, label) =>
    if key != "" {
      counts->Map.set(key, counts->Map.get(key)->Option.getOr(0) + 1)
      if !(labels->Map.has(key)) {
        labels->Map.set(key, String.trim(label))
      }
    }
  all->Array.forEach(e =>
    if matchesFilters(e, f, ~except=facet) && matchesQuery(e, q) {
      switch facet {
      | Category => add(category(e), e.preset.category)
      | Author => add(author(e), e.preset.author)
      | Tag => e.preset.tags->Array.forEach(t => add(norm(t), t))
      }
    }
  )
  let picked = switch facet {
  | Category => f.categories
  | Tag => f.tags
  | Author => f.authors
  }
  picked->Array.forEach(key =>
    if !(counts->Map.has(key)) {
      counts->Map.set(key, 0)
      labels->Map.set(key, key)
    }
  )
  counts
  ->Map.entries
  ->Array.fromIterator
  ->Array.map(((key, n)) => (key, labels->Map.get(key)->Option.getOr(key), n))
  ->Array.toSorted(((ka, _, a), (kb, _, b)) => a != b ? Int.toFloat(b - a) : String.localeCompare(ka, kb))
}
