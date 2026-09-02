package api

import "context"

type ctxKeyOwnerID struct{}

func ctxWithOwnerID(ctx context.Context, oid int64) context.Context {
	return context.WithValue(ctx, ctxKeyOwnerID{}, oid)
}

func ownerIDFromCtx(ctx context.Context) int64 {
	if id, ok := ctx.Value(ctxKeyOwnerID{}).(int64); ok {
		return id
	}
	return 0
}
