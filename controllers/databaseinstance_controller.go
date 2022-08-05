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
	"context"

	"github.com/go-logr/logr"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	dacv1alpha1 "jihulab.com/infracreate/go-kube-operator-project-template/api/v1alpha1"
)

// DatabaseInstanceReconciler reconciles a DatabaseInstance object
type DatabaseInstanceReconciler struct {
	client.Client
	Scheme *runtime.Scheme
	// NOTES:
	Recorder record.EventRecorder
}

type requestCtx struct {
	ctx context.Context
	req ctrl.Request
	log logr.Logger
}

//+kubebuilder:rbac:groups=dac.infracreate.com,resources=databaseinstances,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=dac.infracreate.com,resources=databaseinstances/status,verbs=get;update;patch
//+kubebuilder:rbac:groups=dac.infracreate.com,resources=databaseinstances/finalizers,verbs=update

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
// TODO(user): Modify the Reconcile function to compare the state specified by
// the DatabaseInstance object against the actual cluster state, and then
// perform operations to make the cluster state reflect the state specified by
// the user.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.12.1/pkg/reconcile
func (r *DatabaseInstanceReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {

	// NOTES:
	// setup common request context
	reqCtx := requestCtx{
		ctx: ctx,
		req: req,
		log: log.FromContext(ctx).WithValues("DatabaseInstance", req.NamespacedName),
	}

	// # Concepts:
	// ## Controller reconciling handling
	// Start writing your operator procedures, following provides a guideline
	// on reconciling procedures:
	// 1. get object, do check object's existence
	// 2. handles deletion and attach finalizer
	// 3. reconciling processed state handling ASAP:
	//   1. checked .status.observedGeneration
	//   2. checked .status.phase is in an unrecoverable state

	// #1
	dbInst, err := r.getDatabaseInstance(reqCtx)
	if err != nil {
		return checkedRequeueWithError(err, reqCtx.log, "")
	}

	// TODO: refactor following to generics

	// #2
	// examine DeletionTimestamp to determine if object is under deletion
	if dbInst.ObjectMeta.DeletionTimestamp.IsZero() {
		// The object is not being deleted, so if it does not have our finalizer,
		// then lets add the finalizer and update the object. This is equivalent
		// registering our finalizer.
		if !controllerutil.ContainsFinalizer(dbInst, dbInstanceFinalizerName) {
			controllerutil.AddFinalizer(dbInst, dbInstanceFinalizerName)
			if err := r.Update(ctx, dbInst); err != nil {
				return checkedRequeueWithError(err, reqCtx.log, "")
			}
		}
	} else {
		// The object is being deleted
		if controllerutil.ContainsFinalizer(dbInst, dbInstanceFinalizerName) {
			// our finalizer is present, so lets handle any external dependency
			if err := r.deleteExternalResources(reqCtx, dbInst); err != nil {
				// if fail to delete the external dependency here, return with error
				// so that it can be retried
				return checkedRequeueWithError(err, reqCtx.log, "")
			}

			// remove our finalizer from the list and update it.
			controllerutil.RemoveFinalizer(dbInst, dbInstanceFinalizerName)
			if err := r.Update(ctx, dbInst); err != nil {
				return checkedRequeueWithError(err, reqCtx.log, "")
			}
		}

		// Stop reconciliation as the item is being deleted
		return reconciled()
	}

	// #3
	// #3-1
	if dbInst.Status.ObservedGeneration == dbInst.GetObjectMeta().GetGeneration() {
		return reconciled()
	}

	// #3-2
	switch dbInst.Status.Phase {
	case dacv1alpha1.DatabaseInstancePhaseFailed, dacv1alpha1.DatabaseInstancePhaseFailedValidation:
		return reconciled()
	}

	// TODO(user): your logic here
	return reconciled()
}

// SetupWithManager sets up the controller with the Manager.
func (r *DatabaseInstanceReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&dacv1alpha1.DatabaseInstance{}).
		Complete(r)
}

func (r *DatabaseInstanceReconciler) getDatabaseInstance(reqCtx requestCtx) (*dacv1alpha1.DatabaseInstance, error) {
	d := &dacv1alpha1.DatabaseInstance{}
	if err := r.Client.Get(reqCtx.ctx, reqCtx.req.NamespacedName, d); err != nil {
		return nil, err
	}
	return d, nil
}

func (r *DatabaseInstanceReconciler) deleteExternalResources(reqCtx requestCtx, dbInst *dacv1alpha1.DatabaseInstance) error {
	//
	// delete any external resources associated with the cronJob
	//
	// Ensure that delete implementation is idempotent and safe to invoke
	// multiple times for same object.
	return nil
}
