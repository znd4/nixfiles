;; Write your query here like `(node) @capture`,
;; put the cursor under the capture to highlight the matches.
(predicate
  name: (identifier) @match
  (#eq? @match "match")
  parameters: (parameters
    (string) @injection.content
    (#offset! @injection.content 1 0 -1 0)
    (#set! injection.language "regex")
  )
)
