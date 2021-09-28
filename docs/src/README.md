# Introduction

The three main sections of this book are:

- [User Guide](./user-guide): explains basic concepts and interactions
- [Exploration](./explore): documents the process of exploring the design and implementation space for Anoma
- [Specifications](./specs): implementation independent technical specifications

## The source

This book is written using [mdBook](https://rust-lang.github.io/mdBook/) with [mdbook-mermaid](https://github.com/badboy/mdbook-mermaid) for diagrams, it currently lives in the [Anoma repo](https://github.com/anoma/anoma).

To get started quickly, one can:

```shell
# Install dependencies
make dev-deps
# This will open the book in your default browser and rebuild on changes
make serve
```

The mermaid diagrams docs can be found at <https://mermaid-js.github.io/mermaid>.

Contributions to the contents and the structure of this book (nothing is set in stone) should be made via pull requests. Code changes that diverge from the spec should also update this book.
