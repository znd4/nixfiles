;; Write your query here like `(node) @capture`,
;; put the cursor under the capture to highlight the matches.
(predicate
  name: (identifier) @match
  (#eq? @match "match")
  parameters: (parameters
    (string) @pattern
    (#offset! @pattern 1 0 -1 0)
    (#set! injection.content @pattern)
    (#set! injection.language "regex")
  )
)
