<?hh
function piped(): int {
  $a = Foo::aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa()
    ->h(f()
      |> g($$)
      |> h($$));
}
