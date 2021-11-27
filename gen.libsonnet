local k8s = import 'kubernetes-spec-v1.23/api__v1_openapi.json';

local getVersionInDefinition(definition, version) =
  local versions = [
    v
    for v in definition.spec.versions
    if v.name == version
  ];
  if std.length(versions) == 0
  then error 'version %s in definition %s not found' % [version, definition.metadata.name]
  else if std.length(versions) > 1
  then error 'multiple versions match %s in definition' % [version, definition.metadata.name]
  else versions[0];

local createFunction(name, parents) =
  {
    ['with' + std.asciiUpper(name[0]) + name[1:]](value):
      std.foldr(
        function(p, acc)
          if p == name
          then acc
          else { [p]+: acc }
        ,
        parents,
        { [name]: value }
      ),
  };

local appendFunction(name, parents) =
  {
    ['with' + std.asciiUpper(name[0]) + name[1:] + 'Mixin'](value):
      std.foldr(
        function(p, acc)
          if p == name
          then acc
          else { [p]+: acc }
        ,
        parents,
        { [name]+: [value] }
      ),
  };

local propertyToValue(name, parents, property, debug=false) =
  local infoMessage(message, return) =
    if debug
    then std.trace('INFO: ' + message, return)
    else return;

  local handleObject(name, parents, properties) =
    std.foldl(
      function(acc, p)
        acc {
          [name]+: propertyToValue(
            p,
            parents + [p],
            properties[p],
            debug
          ),
        },
      std.objectFields(properties),
      {}
    );

  local type =
    if std.objectHas(property, 'type')
    then property.type

    // TODO: figure out how to handle allOf, oneOf or anyOf properly,
    // would we expect 'array' or 'object' here?
    else if std.objectHas(property, 'allOf')
            || std.objectHas(property, 'oneOf')
            || std.objectHas(property, 'anyOf')
    then 'xOf'

    else if std.objectHas(property, '$ref')
    then 'ref'

    else infoMessage("can't find type for " + std.join('.', parents), '')
  ;

  createFunction(name, parents)
  + (
    if type == 'array'
    then appendFunction(name, parents)

    else if type == 'object'
            && name == 'metadata'
    then handleObject(
      name,
      parents,
      k8s.components.schemas['io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta'].properties
    )

    else if type == 'object'
            && std.objectHas(property, 'properties')
    then handleObject(
      name,
      parents,
      property.properties
    )

    else {}
  ) + (
    if std.objectHas(property, 'items')

    then (
      if std.objectHas(property.items, 'type')
         && std.member(['array', 'object'], property.items.type)
      then handleObject(
        name,
        parents,
        property.items.properties
      )

      else if std.objectHas(property.items, '$ref')
      then
        // NOTE: big assumption that $ref refers to k8s components only
        local ref = std.split(property.items['$ref'], '/')[3];
        handleObject(
          name,
          parents,
          k8s.components.schemas[ref].properties
        )

      else if !std.objectHas(property.items, 'type')
              && std.objectHas(property.items, '$ref')
      then infoMessage("can't find type or ref for items in " + std.join('.', parents), {})

      else {}
    )
    else {}
  );

{
  generate(definition, debug=false):
    local kind = definition.spec.names.kind;
    std.foldl(
      function(acc, v)
        acc {
          [v]+: {
            [std.asciiLower(kind[0]) + kind[1:]]:
              local schema =
                getVersionInDefinition(definition, v).schema.openAPIV3Schema;
              std.foldl(
                function(acc, p)
                  acc + propertyToValue(
                    p,
                    [p],
                    schema.properties[p],
                    debug
                  ),
                std.objectFields(schema.properties),
                {}
              )
              + {
                new(name):
                  self.withApiVersion(definition.spec.group + '/' + v)
                  + self.withKind(kind)
                  + self.metadata.withName(name),
              },
          },
        },
      [
        version.name
        for version in definition.spec.versions
      ],
      {}
    ),

  local this = self,
  inspect(name, fields):
    std.foldl(
      function(acc, p)
        acc {
          [name]+:
            if std.isObject(fields[p])
            then
              this.inspect(
                p,
                fields[p]
              )
            else if std.isFunction(fields[p])
            then { functions+: [p] }
            else { fields+: [p] },
        },
      std.objectFields(fields),
      {}
    ),
}
