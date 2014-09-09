package main

import "fmt"
import "time"

func main() {
	iterations := 100000

	buffered := make(chan int, 1)

	then := time.Now()

	for i:=0; i<iterations; i++ {
		buffered <- i
		_ = <-buffered
	}

	close(buffered)

	fmt.Println(time.Since(then))


	unbuffered := make(chan int)

	then = time.Now()

	go func() {
		for i:=0; i<iterations; i++ {
			unbuffered <- i
		}
		close(unbuffered)
	}()

	for a := range(unbuffered) { _ = a}

	fmt.Println(time.Since(then))


	buflen := iterations/100
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
	fmt.Println(time.Since(then))
}

