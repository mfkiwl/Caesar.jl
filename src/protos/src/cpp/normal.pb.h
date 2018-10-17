// Generated by the protocol buffer compiler.  DO NOT EDIT!
// source: normal.proto

#ifndef PROTOBUF_normal_2eproto__INCLUDED
#define PROTOBUF_normal_2eproto__INCLUDED

#include <string>

#include <google/protobuf/stubs/common.h>

#if GOOGLE_PROTOBUF_VERSION < 2006000
#error This file was generated by a newer version of protoc which is
#error incompatible with your Protocol Buffer headers.  Please update
#error your headers.
#endif
#if 2006001 < GOOGLE_PROTOBUF_MIN_PROTOC_VERSION
#error This file was generated by an older version of protoc which is
#error incompatible with your Protocol Buffer headers.  Please
#error regenerate this file with a newer version of protoc.
#endif

#include <google/protobuf/generated_message_util.h>
#include <google/protobuf/message.h>
#include <google/protobuf/repeated_field.h>
#include <google/protobuf/extension_set.h>
#include <google/protobuf/unknown_field_set.h>
// @@protoc_insertion_point(includes)

// Internal implementation detail -- do not call these.
void  protobuf_AddDesc_normal_2eproto();
void protobuf_AssignDesc_normal_2eproto();
void protobuf_ShutdownFile_normal_2eproto();

class Normal;

// ===================================================================

class Normal : public ::google::protobuf::Message {
 public:
  Normal();
  virtual ~Normal();

  Normal(const Normal& from);

  inline Normal& operator=(const Normal& from) {
    CopyFrom(from);
    return *this;
  }

  inline const ::google::protobuf::UnknownFieldSet& unknown_fields() const {
    return _unknown_fields_;
  }

  inline ::google::protobuf::UnknownFieldSet* mutable_unknown_fields() {
    return &_unknown_fields_;
  }

  static const ::google::protobuf::Descriptor* descriptor();
  static const Normal& default_instance();

  void Swap(Normal* other);

  // implements Message ----------------------------------------------

  Normal* New() const;
  void CopyFrom(const ::google::protobuf::Message& from);
  void MergeFrom(const ::google::protobuf::Message& from);
  void CopyFrom(const Normal& from);
  void MergeFrom(const Normal& from);
  void Clear();
  bool IsInitialized() const;

  int ByteSize() const;
  bool MergePartialFromCodedStream(
      ::google::protobuf::io::CodedInputStream* input);
  void SerializeWithCachedSizes(
      ::google::protobuf::io::CodedOutputStream* output) const;
  ::google::protobuf::uint8* SerializeWithCachedSizesToArray(::google::protobuf::uint8* output) const;
  int GetCachedSize() const { return _cached_size_; }
  private:
  void SharedCtor();
  void SharedDtor();
  void SetCachedSize(int size) const;
  public:
  ::google::protobuf::Metadata GetMetadata() const;

  // nested types ----------------------------------------------------

  // accessors -------------------------------------------------------

  // required double mean = 1;
  inline bool has_mean() const;
  inline void clear_mean();
  static const int kMeanFieldNumber = 1;
  inline double mean() const;
  inline void set_mean(double value);

  // required double std = 2;
  inline bool has_std() const;
  inline void clear_std();
  static const int kStdFieldNumber = 2;
  inline double std() const;
  inline void set_std(double value);

  // @@protoc_insertion_point(class_scope:Normal)
 private:
  inline void set_has_mean();
  inline void clear_has_mean();
  inline void set_has_std();
  inline void clear_has_std();

  ::google::protobuf::UnknownFieldSet _unknown_fields_;

  ::google::protobuf::uint32 _has_bits_[1];
  mutable int _cached_size_;
  double mean_;
  double std_;
  friend void  protobuf_AddDesc_normal_2eproto();
  friend void protobuf_AssignDesc_normal_2eproto();
  friend void protobuf_ShutdownFile_normal_2eproto();

  void InitAsDefaultInstance();
  static Normal* default_instance_;
};
// ===================================================================


// ===================================================================

// Normal

// required double mean = 1;
inline bool Normal::has_mean() const {
  return (_has_bits_[0] & 0x00000001u) != 0;
}
inline void Normal::set_has_mean() {
  _has_bits_[0] |= 0x00000001u;
}
inline void Normal::clear_has_mean() {
  _has_bits_[0] &= ~0x00000001u;
}
inline void Normal::clear_mean() {
  mean_ = 0;
  clear_has_mean();
}
inline double Normal::mean() const {
  // @@protoc_insertion_point(field_get:Normal.mean)
  return mean_;
}
inline void Normal::set_mean(double value) {
  set_has_mean();
  mean_ = value;
  // @@protoc_insertion_point(field_set:Normal.mean)
}

// required double std = 2;
inline bool Normal::has_std() const {
  return (_has_bits_[0] & 0x00000002u) != 0;
}
inline void Normal::set_has_std() {
  _has_bits_[0] |= 0x00000002u;
}
inline void Normal::clear_has_std() {
  _has_bits_[0] &= ~0x00000002u;
}
inline void Normal::clear_std() {
  std_ = 0;
  clear_has_std();
}
inline double Normal::std() const {
  // @@protoc_insertion_point(field_get:Normal.std)
  return std_;
}
inline void Normal::set_std(double value) {
  set_has_std();
  std_ = value;
  // @@protoc_insertion_point(field_set:Normal.std)
}


// @@protoc_insertion_point(namespace_scope)

#ifndef SWIG
namespace google {
namespace protobuf {


}  // namespace google
}  // namespace protobuf
#endif  // SWIG

// @@protoc_insertion_point(global_scope)

#endif  // PROTOBUF_normal_2eproto__INCLUDED
