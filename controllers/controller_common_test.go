/*
Copyright 2022.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
package controllers

import (
	"errors"
	"testing"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime/schema"
	ctrl "sigs.k8s.io/controller-runtime"
)

var tlog = ctrl.Log.WithName("controller_testing")

func TestRequeueWithError(t *testing.T) {
	_, err := checkedRequeueWithError(errors.New("test error"), tlog, "test")
	if err == nil {
		t.Error("Expected error to fall through, got nil")
	}
}

func TestRequeueWithNotFoundError(t *testing.T) {
	notFoundErr := apierrors.NewNotFound(schema.GroupResource{
		Resource: "Pod",
	}, "no-body")
	_, err := checkedRequeueWithError(notFoundErr, tlog, "test")
	if err == nil {
		t.Error("Expected error to fall through, got nil")
	}
}

func TestRequeueAfter(t *testing.T) {
	_, err := requeueAfter(time.Millisecond, tlog, "test")
	if err == nil {
		t.Error("Expected error to fall through, got nil")
	}
}

func TestRequeue(t *testing.T) {
	_, err := requeue(tlog, "test")
	if err == nil {
		t.Error("Expected error to fall through, got nil")
	}
}

func TestReconciled(t *testing.T) {
	res, err := reconciled()
	if err != nil {
		t.Error("Expected error to be nil, got:", err)
	}
	if res.Requeue {
		t.Error("Expected requeue to be false, got true")
	}
}
