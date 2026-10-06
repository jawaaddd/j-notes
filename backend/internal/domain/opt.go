package domain

import "encoding/json"

// Opt is a PATCH field that tells "absent" apart from "null".
// Absent: Set is false. Null: Set is true and Value is nil.
type Opt[T any] struct {
	Set   bool
	Value *T
}

func (o *Opt[T]) UnmarshalJSON(b []byte) error {
	o.Set = true
	if string(b) == "null" {
		o.Value = nil
		return nil
	}
	var v T
	if err := json.Unmarshal(b, &v); err != nil {
		return err
	}
	o.Value = &v
	return nil
}

// Some builds a set, non-null Opt; handy in tests and seeds.
func Some[T any](v T) Opt[T] { return Opt[T]{Set: true, Value: &v} }

// Null builds a set, null Opt.
func Null[T any]() Opt[T] { return Opt[T]{Set: true} }
