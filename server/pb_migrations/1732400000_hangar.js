/// <reference path="../pb_data/types.d.ts" />
// Colecciones de Hangar (PocketBase 0.22): perfiles, amistades, partidas y logros desbloqueados.
migrate((db) => {
  const dao = new Dao(db)

  // Perfiles: los usuarios se ven entre sí (para buscar amigos), el correo no.
  const users = dao.findCollectionByNameOrId("users")
  users.schema.addField(new SchemaField({ name: "nombre", type: "text", required: false, options: { min: null, max: 40, pattern: "" } }))
  users.listRule = "@request.auth.id != ''"
  users.viewRule = "@request.auth.id != ''"
  dao.saveCollection(users)

  const rel = (name) => ({ name, type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, minSelect: null, maxSelect: 1, displayFields: ["nombre"] } })
  const logueado = "@request.auth.id != ''"

  // Amistades: "de" la pide, "para" la acepta.
  dao.saveCollection(new Collection({
    name: "amistades",
    type: "base",
    schema: [rel("de"), rel("para"), { name: "estado", type: "select", required: true, options: { maxSelect: 1, values: ["pendiente", "aceptada"] } }],
    indexes: ["CREATE UNIQUE INDEX idx_amistades ON amistades (de, para)"],
    listRule: "@request.auth.id = de || @request.auth.id = para",
    viewRule: "@request.auth.id = de || @request.auth.id = para",
    createRule: "@request.auth.id != '' && @request.data.de = @request.auth.id && @request.data.estado = 'pendiente'",
    updateRule: "@request.auth.id = para",
    deleteRule: "@request.auth.id = de || @request.auth.id = para",
  }))

  // Partidas: tiempo jugado y última sesión por juego y sistema.
  dao.saveCollection(new Collection({
    name: "partidas",
    type: "base",
    schema: [
      rel("user"),
      { name: "juego", type: "text", required: true, options: { min: 1, max: 120, pattern: "" } },
      { name: "nombre", type: "text", required: false, options: { min: null, max: 200, pattern: "" } },
      { name: "plataforma", type: "select", required: true, options: { maxSelect: 1, values: ["android", "mac"] } },
      { name: "segundos", type: "number", required: false, options: { min: 0, max: null, noDecimal: true } },
      { name: "ultima", type: "date", required: false, options: { min: "", max: "" } },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_partidas ON partidas (user, juego, plataforma)"],
    listRule: logueado,
    viewRule: logueado,
    createRule: "@request.data.user = @request.auth.id",
    updateRule: "user = @request.auth.id",
    deleteRule: "user = @request.auth.id",
  }))

  // Logros desbloqueados (de cada juego o de Hangar).
  dao.saveCollection(new Collection({
    name: "desbloqueos",
    type: "base",
    schema: [
      rel("user"),
      { name: "juego", type: "text", required: true, options: { min: 1, max: 120, pattern: "" } },
      { name: "fuente", type: "text", required: true, options: { min: 1, max: 40, pattern: "" } },
      { name: "logro", type: "text", required: true, options: { min: 1, max: 120, pattern: "" } },
      { name: "fecha", type: "date", required: false, options: { min: "", max: "" } },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_desbloqueos ON desbloqueos (user, juego, fuente, logro)"],
    listRule: logueado,
    viewRule: logueado,
    createRule: "@request.data.user = @request.auth.id",
    updateRule: "user = @request.auth.id",
    deleteRule: "user = @request.auth.id",
  }))
}, (db) => {
  const dao = new Dao(db)
  for (const n of ["desbloqueos", "partidas", "amistades"]) {
    try { dao.deleteCollection(dao.findCollectionByNameOrId(n)) } catch (_) {}
  }
  const users = dao.findCollectionByNameOrId("users")
  users.schema.removeField(users.schema.getFieldByName("nombre").id)
  users.listRule = "id = @request.auth.id"
  users.viewRule = "id = @request.auth.id"
  dao.saveCollection(users)
})
