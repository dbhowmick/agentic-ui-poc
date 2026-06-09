[
  # `jido_action` 1.x ships a Zoi.map/2 call that upstream Zoi has since
  # narrowed; warnings appear inside the dependency, not in our code.
  # Tracked upstream — revisit when the dep bumps Zoi compatibility.
  ~r{deps/jido_action/.+}
]
