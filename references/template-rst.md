# Change History Template: reStructuredText

Covers: `.rst`

Place at the end of the file. The `..` RST comment directive causes Sphinx to discard the block entirely; it never surfaces in built HTML or PDF output.

```rst
..

   Change History

   PR     Summary
   -----  -----------------------------------------------------------------
   #N     one-line description
```

Note: pipe-table syntax (`| col |`) must not be used inside RST `..` comments — the RST parser expands `|...|` as substitution references even inside comment blocks. Use plain aligned text columns instead.
