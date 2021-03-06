<?hh // strict
/**
 * Copyright (c) 2014, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the "hack" directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *
 */

class TestGeneric<T> {
  private T $obj;

  public function __construct(T $obj) {
    $this->obj = $obj;
  }

  public function get(): T {
    return $this->obj;
  }
}

class X<T, Tc as TestGeneric<T> > {
  public Vector<T> $vec;

  public function __construct(Vector<Tc> $tests) {
    $results = Vector {};
    foreach ($tests as $test) {
      $results[] = $test->get();
    }
    $this->vec = $results;
  }


}

function testBool(bool $arg): void {}

function test(): void {
  $objs = Vector {
    new TestGeneric(1),
    new TestGeneric(2),
  };
  
  $results = (new X($objs))->vec;
  foreach ($results as $result) {
    // Hack should complain it's an int !
    testBool($result);
  }
}
