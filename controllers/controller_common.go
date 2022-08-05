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
	"time"

	"github.com/go-logr/logr"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"
)

const (
	// name of our custom finalizer
	dbInstanceFinalizerName = "databaseinstances.infracreate.com/finalizer"
)

// reconciled returns an empty result with nil error to signal a successful reconcile
// to the controller manager
func reconciled() (reconcile.Result, error) {
	return reconcile.Result{}, nil
}

// checkedRequeueWithError is a convenience wrapper around logging an error message
// separate from the stacktrace and then passing the error through to the controller
// manager, this will ignore not-found errors.
func checkedRequeueWithError(err error, logger logr.Logger, msg string, keysAndValues ...string) (reconcile.Result, error) {
	if apierrors.IsNotFound(err) {
		return reconciled()
	}
	if msg == "" {
		logger.Info(err.Error())
	} else {
		// Info log the error message and then let the reconciler dump the stacktrace
		logger.Info(msg, keysAndValues)
	}
	return reconcile.Result{}, err
}

func requeueAfter(duration time.Duration, logger logr.Logger, msg string, keysAndValues ...string) (reconcile.Result, error) {
	if msg != "" {
		logger.Info(msg, keysAndValues)
	} else {
		logger.V(1).Info("retry-after", "duration", duration)
	}
	return reconcile.Result{
		Requeue:      true,
		RequeueAfter: duration,
	}, nil
}

func requeue(logger logr.Logger, msg string, keysAndValues ...string) (reconcile.Result, error) {
	if msg != "" {
		logger.Info(msg, keysAndValues)
	} else {
		logger.V(1).Info("requeue")
	}
	return reconcile.Result{Requeue: true}, nil
}
