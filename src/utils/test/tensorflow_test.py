# Python でテスト
import tensorflow as tf
import numpy as np
print("TensorFlow version:", tf.__version__)
print("NumPy version:", np.__version__)

# 簡単な動作テスト
x = tf.constant([1, 2, 3])
print("TensorFlow working:", x)