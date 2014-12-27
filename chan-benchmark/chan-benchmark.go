package main

import "fmt"
import "time"

func main() {
	iterations := 120000
	buflen := iterations/1000

	buffered := make(chan int, 1)

	then := time.Now()

	for i:=0; i<iterations; i++ {
		buffered <- i
		_ = <-buffered
	}

	close(buffered)

	fmt.Print(time.Since(then))
	fmt.Print("\t(")
	fmt.Print(time.Since(then)/time.Duration(iterations))
	fmt.Println(" per message)")


	buffered = make(chan int, 1)

	then = time.Now()

	go func() {
		for i:=0; i<iterations; i++ {
			buffered <- i
		}
		close(buffered)
	}()

	for a := range(buffered) { _ = a }

	fmt.Print(time.Since(then))
	fmt.Print("\t(")
	fmt.Print(time.Since(then)/time.Duration(iterations))
	fmt.Println(" per message)")


	unbuffered := make(chan int)

	then = time.Now()

	go func() {
		for i:=0; i<iterations; i++ {
			unbuffered <- i
		}
		close(unbuffered)
	}()

	for a := range(unbuffered) { _ = a}

	fmt.Print(time.Since(then))
	fmt.Print("\t(")
	fmt.Print(time.Since(then)/time.Duration(iterations))
	fmt.Println(" per message)")


	bufferedN := make(chan int, buflen)

	then = time.Now()
	for j:=0; j<(iterations/buflen); j++ {

		for i:=0; i<buflen; i++ {
			bufferedN <- i
		}

		for i:=0; i<buflen; i++ {
			_ = <-bufferedN
		}
	}
	close(bufferedN)

	fmt.Print(time.Since(then))
	fmt.Print("\t(")
	fmt.Print(time.Since(then)/time.Duration(iterations))
	fmt.Println(" per message)")


	bufferedN = make(chan int, buflen)

	then = time.Now()
	go func() {
		for i:=0; i<iterations; i++ {
			bufferedN <- i
		}
		close(bufferedN)
	}()

	for a := range(bufferedN) { _ = a}

	fmt.Print(time.Since(then))
	fmt.Print("\t(")
	fmt.Print(time.Since(then)/time.Duration(iterations))
	fmt.Println(" per message)")
}

