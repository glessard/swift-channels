//
//  main.swift
//  chan-select
//
//  Created by Guillaume Lessard on 2014-08-28.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

let a = Chan<Int>.Make(1)
let b = Chan<Int>.Make(1)
let c = Chan<Int>.Make(1)
let d = Chan<Int>.Make(1)//SingletonChan<Int>()
let e = Chan<Int>.Make(1)

let chans = [a,b,c,d,e]

let tic = Time()

async {
  for i in 1...1000
  {
    let index = Int(arc4random_uniform(UInt32(chans.count)))
//    syncprint("Round \(i): sending on channel \(index)")
    chans[index] <- index
//    Time.Wait(10)
  }

  for chan in chans
  {
    chan.close()
  }
}

var i = 0
forever: while true
{
  let (selected,p) = Select(a,b,c,d,e)
  switch selected
  {
  case let z where z === a:
    if let p = a.extract(p) { i++ }
    break
  case let z where z === b:
    if let p = b.extract(p) { i++ }
    break
  case let z where z === c:
    if let p = c.extract(p) { i++ }
    break
  case let z where z === d:
    if let p = d.extract(p) { i++ }
    break
  case let z where z === e:
    if let p = e.extract(p) { i++ }
    break
  default:
    syncprint("every channel is closed and empty")
    break forever
  }
}

syncprint("\(i) messages received")
syncprint(tic.toc)
syncprintwait()
