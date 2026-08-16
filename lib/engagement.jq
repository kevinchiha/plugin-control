# Reduces the marketplace counter service payload to the three counts the
# palette sorts on. The service is a separate host from the catalog, so every
# value here is treated as untrusted: identifiers that could escape a cache
# path are dropped, and anything that is not a sane whole number becomes zero
# rather than poisoning a sort with NaN.

def bounded_count($key):
  (.[$key] // 0)
  | if type == "number" and . >= 0 and . <= 100000000 then floor else 0 end;

def valid_plugin_id:
  type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$");

if type != "object" then
  {ok: false, error: "counts root must be an object", counts: {}}
elif (.schemaVersion != null and .schemaVersion != 1) then
  {ok: false, error: "unsupported counts schema version", counts: {}}
elif (.plugins | type) != "object" then
  {ok: false, error: "counts plugins must be an object", counts: {}}
elif (.plugins | length) > 5000 then
  {ok: false, error: "counts has too many records", counts: {}}
else
  {
    ok: true,
    counts: (
      .plugins
      | to_entries
      | map(select((.key | valid_plugin_id) and (.value | type == "object")))
      | map({
          key: .key,
          value: {
            views: (.value | bounded_count("views")),
            copies: (.value | bounded_count("copies")),
            hearts: (.value | bounded_count("hearts"))
          }
        })
      | from_entries
    )
  }
end
