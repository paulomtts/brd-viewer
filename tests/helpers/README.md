# Test helpers

`find.js` is a `.pragma library` with `find(item, name)`, a depth-first search by
`objectName` through `children`, `data` and `contentItem`. Import it from a QML
test with a path relative to the test file:

    .import "../helpers/find.js" as H

(`import "../helpers/find.js" as H` in tests under `tests/ui`; adjust the `..`
count for deeper folders.)
