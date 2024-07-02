+++
title = "Extractig Generic Substates in Axum"
[taxonomies]
tags = ["rust", "axum"]
+++

In this post I'll show you how to extract a generic substate in Axum handlers, without resorting to dynamic dispatch.

<!-- more -->

# An Intro to Substates in Axum

The Axum Web framework allows you to easily extract parts of your application states in handlers:

```rust
// Some service
struct GuestGreeter;
impl GuestGreeter { /* ... */ }

// Our Axum handler that uses the greeter service
async fn homepage_handler(State(greeter): State<GuestGreeter>) -> impl IntoResponse { /* ... */ }

// Application state
struct AppState {
    greeter: GuestGreeter,
}

// manual `FromRef` implementation
impl FromRef<AppState> for GuestGreeter {
    fn from_ref(state: &AppState) -> Self {
        state.greeter.clone()
    }
}

// Putting it all together now ...
async fn start_app(greeter: GuestGreeter) {
    let state = AppState { greeter };
    let app = Router::new()
        .route("/", get(homepage_handler))
        .with_state(state);

    /* ... */
}
```

# Making it Generic

This works perfectly now and we can extend `AppState` with more components.
However when following DDD or Hexagonal Architecture, you'll usually want your AppState and handlers to be generic over your domain's traits.

So let's start with the Trait and some implementors:

```rust
trait Greeter: Clone + Send + Sync + 'static { /* ... */ }

impl Greeter for WorldGreeter { /* ... */ }
impl Greeter for UniverseGreeter { /* ... */ }
```

One thig to note here is the additional trait bounds on `Greeter`.
While `Clone` is required for any state you pass into Axum (unless you wrap it in an `Arc`), `Send + Sync` ensure that it can be shared & passed between threads.

Next, our handler and state should of course be generic as well:

```rust
async fn homepage<G: Greeter>(State(greeter): State<G>) -> { /* ... */ }

struct AppState<G: Greeter> {
    greeter: G,
}
```

Now when it comes to `AsRef`, it's unfortunately NOT possible (or at least I did not find out how) to just have a generic implementation:

```rust
impl<G: Greeter> FromRef<AppState<G>> for G {
    fn from_ref(state: &AppState<G>) -> Self {
        state.greeter.clone()
    }
}
```

This results in a compilation error:

```sql
 32 | impl<G: Greeter> FromRef<AppState<G>> for G {
    |      ^ type parameter `G` must be covered by another type when it appears before the first local type (`AppState<G>`)
```

So instead we have to implement `AsRef` for each concrete type:

```rust
impl FromRef<AppState<UniverseGreeter>> for UniverseGreeter { /* ... */ }
impl FromRef<AppState<WorldGreeter>> for WorldGreeter { /* ... */ }
```

Now the only thing missing is our `run_app`:

```rust
async fn run_app<G>(greeter: G)
where
    G: Greeter + FromRef<AppState<G>>,  // <1>
{
    let state = AppState { greeter };
    let app = Router::new()
        .route("/", get(homepage::<G>))  // <2>
        .with_state(state);

    /* ... */
}
```

Now there are quite a few important bits:

1. `G` must also be constrained by `FromRef<AppState<G>>`
2. We must pass our generic param to the handler function using the turbofish syntax: `homepage::<G>`

# Summary

TL;DR:

- Implement `AsRef<AppState<...>>` for each concrete type
- When building the Router, pass any generics to the handlers: `handler::<...>`
- When building the Router, ensure generics are constrained by `FromRef<AppState<G>>`

_Got any feedback or input? Ping me on Masto at [@dratir@masto.ai](https://masto.ai/@dratir)!_
