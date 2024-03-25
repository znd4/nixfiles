(block
  name: (expr)
  (#eq? @name "QUERY")
  contents: (contents @injection.content) 
  (#set! @injection.language "clojure")
)
