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

package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// DatabaseInstanceSpec defines the desired state of DatabaseInstance
type DatabaseInstanceSpec struct {
	// INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	// Foo is an example field of DatabaseInstance. Edit databaseinstance_types.go to remove/update
	Foo string `json:"foo,omitempty"`
}

// DatabaseInstancePhase is a string representation of the lifecycle phase
// of a database instance.
// +kubebuilder:validation:Enum=New;FailedValidation;Failed;Creating;Running;Deleting
type DatabaseInstancePhase string

const (
	// DatabaseInstancePhaseNew means the object has been created but not
	// yet processed by the Controller.
	DatabaseInstancePhaseNew DatabaseInstancePhase = "New"

	// DatabaseInstancePhaseFailedValidation means the object has failed
	// the controller's validations and therefore will not run.
	DatabaseInstancePhaseFailedValidation DatabaseInstancePhase = "FailedValidation"

	// DatabaseInstancePhaseFailed means the object ran but encountered an error.
	DatabaseInstancePhaseFailed DatabaseInstancePhase = "Failed"

	// DatabaseInstancePhaseDeleting means the object and all its associated data are being deleted.
	DatabaseInstancePhaseDeleting DatabaseInstancePhase = "Deleting"

	// DatabaseInstancePhaseCreating means the object's controller are at in-process of creating a database instance.
	DatabaseInstancePhaseCreating DatabaseInstancePhase = "Creating"

	// DatabaseInstancePhaseRunning means the object's associated database instance is in a running status.
	DatabaseInstancePhaseRunning DatabaseInstancePhase = "Running"
)

// DatabaseInstanceStatus defines the observed state of DatabaseInstance
type DatabaseInstanceStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	// The generation observed by the controller.
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`

	// Phase is the current state of the DatabaseInstance.
	// +optional
	Phase DatabaseInstancePhase `json:"phase,omitempty"`

	// FailureReason is an error message for FailedValidation/Failed phase.
	// +optional
	FailureReason string `json:"failureReason,omitempty"`
}

//+kubebuilder:object:root=true
//+kubebuilder:subresource:status

// DatabaseInstance is the Schema for the databaseinstances API
type DatabaseInstance struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   DatabaseInstanceSpec   `json:"spec,omitempty"`
	Status DatabaseInstanceStatus `json:"status,omitempty"`
}

//+kubebuilder:object:root=true

// DatabaseInstanceList contains a list of DatabaseInstance
type DatabaseInstanceList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []DatabaseInstance `json:"items"`
}

func init() {
	SchemeBuilder.Register(&DatabaseInstance{}, &DatabaseInstanceList{})
}
