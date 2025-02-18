(block
  name: (expr) @name
  (#eq? @name "QUERY")
  contents: (contents) @injection.content 
  (#set! injection.include-children true)
  (#set! injection.language "clojure")
)
