# Overview

The `Audacia.Build` repo contains multiple different general purpose yaml files to be consumed by other pipelines. It is structured by feature area, so all code and documentation related to a specific feature area is located in a single folder. For example, everything related OWASP ZAP is in the `src/security/owasp-zap` folder.

Each feature folder may contain some or all of:

- Template jobs in a `jobs` folder
  - These should only be used where necessary to avoid extra layers
- Template collections of steps in a `steps` folder
  - These are collections of tasks to complete a common outcome
- Small units of reusable step(s) in a `tasks` folder
  - These are one or more steps performing a single logical task. These should avoid wrapping existing tasks, unless providing extra common functionality with parameters

# How to use

These yaml files should be consumed by your pipelines. You can reference this repository as a resource at the root of your pipeline:

```yaml
resources:
  repositories:
    - repository: templates
      type: github
      endpoint: 'Github Service Connection'
      name: audaciaconsulting/Audacia.Build
```

You can then reference any of these yaml files as templates, e.g.:

```yaml
steps:
  - template: /src/build/dotnet/steps/net-core.steps.yaml@templates
    parameters:
      projects: '**/*.Api.csproj'
      tests: '**/*.Tests.csproj'
      artifactName: 'Api'
```

The repository resource requires a Service Connection to GitHub in your DevOps project, as specified by the `endpoint` property. For Audacia projects, both those in our DevOps or a client's DevOps, please speak to IT.

# Contributing

We welcome contributions! Please feel free to check our [Contribution Guidelines](https://github.com/audaciaconsulting/.github/blob/main/CONTRIBUTING.md) for feature requests, issue reporting and guidelines.
