# Search API schema — synthetic fixture, revision 3
Source ID: SEARCH-SCHEMA-3; scope: POST /search.
Supported request encodings: flat snake_case object and c2s wrapper containing snake_case object. Semantic result must match for equal normalized inputs.
camelCase keys and mixed wrappers are rejected with 400 and zero search side effects. Unsupported fields are not silently accepted.
No fourth supported format exists in this contract. Other routes are outside scope.
