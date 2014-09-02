package main

import "fmt"
import "time"

func main() {
	iterations := 100000

	buffered := make(chan int, 1)

	then := time.Now()

	for i:=0; i<iterations; i++ {
		buffered <- i
		a := <-buffered
		_ = a
	}

	close(buffered)

	fmt.Println(time.Since(then))


	unbuffered := make(chan int, 1)

	then = time.Now()

	go func() {
		for i:=0; i<iterations; i++ {
			unbuffered <- i
		}
		close(unbuffered)
	}()

	for a := range(unbuffered) { _ = a}

	fmt.Println(time.Since(then))
}

